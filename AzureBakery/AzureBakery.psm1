

using namespace Microsoft.Azure.Commands.Common.Authentication.Abstractions

Import-Module "AzureRm"


<#
.SYNOPSIS
Bakes Windows Features and Updates into the latest version of Windows Server

.DESCRIPTION
Creates a VHD in the specified storage container containing the specified Windows Features and all Windows Updates.

.PARAMETER StorageContext
Azure Storage context used to interact with the Azure Storage PowerShell API.

.PARAMETER WindowsFeature
Array of Windows Features and Roles to be installed on the generalized image.  Feature names must be same as from Get-WindowsFeature.

.PARAMETER StorageContainer
Blob storage container name where the baked VHD will be placed

.PARAMETER TempResourceName
Globally unique identifier used to name temporary resources

.PARAMETER ImageName
Blob name of the baked VHD
Default value: "BakedWindows.$(Get-Date -Format "yyMMddHHmm").vhd"

.PARAMETER Location
Region where temporary resources are created.

.EXAMPLE
# Get the Azure Storage context
$ctx = (Get-AzureRmStorageAccount -Name "contosostorage").Context

# Creates a fully updated Windows VHD with the "Web-Server" and "Web-Asp-Net" features installed.
# The VHD is located in contosostorage.blob.core.windows.net/images
New-BakedImage -StorageContext $ctx -WindowsFeature "Web-Server", "Web-Asp-Net"

# Creates a fully updated Windows VHD with the "Web-Server" and "Web-Asp-Net" features installed.
New-BakedImage -StorageContext $ctx -WindowsFeature "Web-Server", "Web-Asp-Net" -

.NOTES
Log into Azure before running this cmdlet
#>
function New-BakedImage {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [IStorageContext]$StorageContext,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$WindowsFeature,
        [ValidateNotNullOrEmpty()]
        [string]$StorageContainer = "images",
        [ValidateNotNullOrEmpty()]
        [string]$TempResourceName = ("temp$(New-Guid)" -replace "[^\w\d]").Substring(0, 24),
        [ValidateNotNullOrEmpty()]
        [string]$ImageName = "BakedWindows.$(Get-Date -Format "yyMMddHHmm").vhd",
        [ValidateNotNullOrEmpty()]
        [string]$Location = "East US"
    )


    $ErrorActionPreference = "Stop"
    $InformationPreference = "Continue"
    $VerbosePreference = "Continue"

    <##
     # Fail-fast error checking
     #>

    if (-not (Get-AzureRmContext).Account) {
        throw "Run Login-AzureRmAccount to continue"
    }

    Write-Information "Using name '$TempResourceName'"


    <## 
     # Package DSC
     #>

    Write-Information "Packaging DSC"

    Write-Verbose "Zipping '$PSScriptRoot\dsc.ps1' to '$env:TEMP\dsc.zip'"
    Publish-AzureRmVMDscConfiguration `
        -ConfigurationPath "$PSScriptRoot\dsc.ps1" `
        -OutputArchivePath "$env:TEMP\dsc.zip" `
        -Force `
        | Out-Null


    <##
     # Upload artifacts
     #>

    Write-Information "Uploading artifacts"

    Write-Verbose "Creating resource group '$TempResourceName'"
    New-AzureRmResourceGroup -Name $TempResourceName -Location $Location | Out-Null

    Write-Verbose "Creating storage account '$TempResourceName'"
    $storageAccount = New-AzureRmStorageAccount `
        -ResourceGroupName $TempResourceName `
        -Name $TempResourceName `
        -SkuName Standard_LRS `
        -Location $Location

    Write-Verbose "Creating storage container 'artifacts'"
    New-AzureStorageContainer `
        -Name "artifacts" `
        -Context $storageAccount.Context `
        | Out-Null

    Write-Verbose "Uploading '$env:TEMP\dsc.zip' to 'artifacts\dsc.zip'"
    Set-AzureStorageBlobContent `
        -File "$env:TEMP\dsc.zip" `
        -Container "artifacts" `
        -Blob "dsc.zip" `
        -Context $storageAccount.Context `
        | Out-Null

    Write-Verbose "Uploading '$PSScriptRoot\cse.ps1' to 'artifacts\cse.ps1'"
    Set-AzureStorageBlobContent `
        -File "$PSScriptRoot\cse.ps1" `
        -Container "artifacts" `
        -Blob "cse.ps1" `
        -Context $storageAccount.Context `
        | Out-Null

    Write-Verbose "Generating 2hr SAS token for 'artifacts'"
    $sasToken = New-AzureStorageContainerSASToken `
        -Name "artifacts" `
        -Permission "r" `
        -StartTime (Get-Date) `
        -ExpiryTime (Get-Date).AddHours(2) `
        -Context $storageAccount.Context


    <##
     # Deploy
     #>

    Write-Information "Deploying"

    # create the infra and run the DSC
    Write-Verbose "Deploying resource group"
    New-AzureRmResourceGroupDeployment `
        -Name ((Get-Date -Format "s") -replace "[^\d]") `
        -ResourceGroupName $TempResourceName `
        -TemplateFile "$PSScriptRoot\template.json" `
        -DscUrl "https://$TempResourceName.blob.core.windows.net/artifacts/dsc.zip$sasToken" `
        -WindowsFeature $WindowsFeature `
        | Out-Null

    # remove the DSC and generalize the VM
    Write-Verbose "Get a reference to the VM"
    $Vm = Get-AzureRmVM -ResourceGroupName $TempResourceName
    $VmName = $Vm.Name
    $VmDiskName = $Vm.StorageProfile.OsDisk.Name

    Write-Verbose "Remove the DSC extension"
    Remove-AzureRmVMDscExtension -ResourceGroupName $TempResourceName -VMName $VmName | Out-Null

    Write-Verbose "Saving the Azure context"
    Save-AzureRmContext -Path "$env:TEMP\.azurebakery.context.json" -Force

    # sysprep the VM in a job so we can kill it before it times out
    Write-Verbose "Add the CSE extension to sysprep the VM"
    $job = Start-Job {
        Import-AzureRmContext -Path "$env:TEMP\.azurebakery.context.json"
        Set-AzureRmVMCustomScriptExtension `
            -ResourceGroupName $using:TempResourceName `
            -VMName $using:VmName `
            -Location $using:Location `
            -FileUri "https://$using:TempResourceName.blob.core.windows.net/artifacts/cse.ps1$using:sasToken" `
            -Run "cse.ps1" `
            -Name "SysprepVm" `
            -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds (10 * 60)
    $job | Stop-Job | Remove-Job -Force

    # stop and generalize the VM
    Write-Verbose "Stop the VM"
    Stop-AzureRmVM -ResourceGroupName $TempResourceName -Name $VmName -Force | Out-Null
    Write-Verbose "Generalize the VM"
    Set-AzureRmVM -ResourceGroupName $TempResourceName -Name $VmName -Generalized | Out-Null

    # copy the internal disk blob to a normal blob storage container
    # adapted from https://blogs.msdn.microsoft.com/igorpag/2017/03/14/azure-managed-disks-deep-dive-lessons-learned-and-benefits/
    Write-Verbose "Lock the OS disk for copy"
    $diskUrl = Grant-AzureRmDiskAccess `
        -ResourceGroupName $TempResourceName `
        -DiskName $VmDiskName `
        -Access Read `
        -DurationInSecond 3600 `
        | % {$_.AccessSAS}
    Write-Verbose "Copy the disk to blob storage"
    Start-AzureStorageBlobCopy `
        -AbsoluteUri $diskUrl `
        -DestBlob $ImageName `
        -DestContainer $StorageContainer `
        -DestContext $StorageContext `
        -Force `
        | Out-Null
    Get-AzureStorageBlobCopyState `
        -Container $StorageContainer `
        -Blob $ImageName `
        -Context $StorageContext `
        -WaitForComplete `
        | Out-Null
    Write-Verbose "Unlock the OS disk for deletion"
    Revoke-AzureRmDiskAccess `
        -ResourceGroupName $TempResourceName `
        -DiskName $VmDiskName `
        | Out-Null

    # clean up
    Write-Verbose "Delete '$TempResourceName'"
    # Remove-AzureRmVM -ResourceGroupName $TempResourceName -Name $TempResourceName -Force | Out-Null
    Remove-AzureRmResourceGroup -Name $TempResourceName -Force | Out-Null

    return "$($StorageContext.BlobEndPoint)$StorageContainer/$ImageName"
}
