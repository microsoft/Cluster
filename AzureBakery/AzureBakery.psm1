
function New-BakedImage {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ImageResourceGroupName,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty(Mandatory)]
        [string[]]$WindowsFeature,
        [ValidateNotNullOrEmpty()]
        [string]$Name = ("temp$(New-Guid)" -replace "[^\w\d]").Substring(0, 24),
        [ValidateNotNullOrEmpty()]
        [string]$Location = "East US"
    )


    $ErrorActionPreference = "Stop"


    <##
     # Fail-fast error checking
     #>

    if (-not (Get-AzureRmContext).Account) {
        throw "Run Login-AzureRmAccount to continue"
    }

    if (-not (Get-AzureRmResourceGroup -Name $ImageResourceGroupName)) {
        throw "Resource Group '$ImageResourceGroupName' does not exist"
    }


    Write-Information "Using name '$Name'"


    <## 
     # Package DSC
     #>

    Write-Information "Packaging DSC"

    Write-Verbose "Writing WindowsFeatures to '$env:TEMP\WindowsFeatures.txt'"
    $WindowsFeature | Out-File -FilePath "$env:TEMP\WindowsFeatures.txt" -Force

    Write-Verbose "Zipping '$PSScriptRoot\dsc.ps1', '$env:TEMP\WindowsFeatures.txt' to '$env:TEMP\dsc.zip'"
    Publish-AzureRmVMDscConfiguration `
        -ConfigurationPath "$PSScriptRoot\dsc.ps1" `
        -OutputArchivePath "$env:TEMP\dsc.zip" `
        -AdditionalPath "$env:TEMP\WindowsFeatures.txt" `
        -Force


    <##
     # Upload artifacts
     #>

    Write-Information "Uploading artifacts"

    Write-Verbose "Creating resource group '$Name'"
    New-AzureRmResourceGroup -Name $Name -Location $Location 

    Write-Verbose "Creating storage account '$Name'"
    $storageAccount = New-AzureRmStorageAccount `
        -ResourceGroupName $Name `
        -Name $Name `
        -SkuName Standard_LRS `
        -Location $Location

    Write-Verbose "Creating storage container 'artifacts'"
    New-AzureStorageContainer `
        -Name "artifacts" `
        -Context $storageAccount.Context

    Write-Verbose "Uploading '$env:TEMP\dsc.zip' to 'artifacts\dsc.zip'"
    Set-AzureStorageBlobContent `
        -File "$env:TEMP\dsc.zip" `
        -Container "artifacts" `
        -Blob "dsc.zip" `
        -Context $storageAccount.Context

    Write-Verbose "Uploading '$PSScriptRoot\cse.ps1' to 'artifacts\cse.ps1'"
    Set-AzureStorageBlobContent `
        -File "$PSScriptRoot\cse.ps1" `
        -Container "artifacts" `
        -Blob "cse.ps1" `
        -Context $storageAccount.Context

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
        -ResourceGroupName $Name `
        -TemplateFile "$PSScriptRoot\template.json" `
        -DscUrl "https://$Name.blob.core.windows.net/artifacts/dsc.zip$sasToken"

    # remove the DSC and generalize the VM
    Write-Verbose "Get a reference to the VM"
    $Vm = Get-AzureRmVM -ResourceGroupName $Name
    Write-Verbose "Remove the DSC extension"
    Remove-AzureRmVMDscExtension -ResourceGroupName $Name -VMName $Vm.Name
    Write-Verbose "Add the CSE extension (this will take a while)"
    Set-AzureRmVMCustomScriptExtension `
        -ResourceGroupName $Name `
        -VMName $Vm.Name `
        -Location $Location `
        -FileUri "https://$Name.blob.core.windows.net/artifacts/cse.ps1$sasToken" `
        -Run "cse.ps1" `
        -Name "SysprepVm" `
        -ErrorAction SilentlyContinue

    # harvest the image from the VM
    Write-Verbose "Stop the VM"
    Stop-AzureRmVM -ResourceGroupName $Name -Name $VM.Name -Force
    Write-Verbose "Generalize the VM"
    Set-AzureRmVM -ResourceGroupName $Name -Name $VM.Name -Generalized
    Write-Verbose "Save the image"
    New-AzureRmImage `
        -Image (New-AzureRmImageConfig -Location $Location -SourceVirtualMachineId $Vm.Id) `
        -ImageName (Get-Date -Format "yyyyMMdd") `
        -ResourceGroupName $ImageResourceGroupName

    # clean up
    Write-Verbose "Delete '$Name'"
    Remove-AzureRmResourceGroup -Name $Name -Force
}
