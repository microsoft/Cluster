
Import-Module "$PSScriptRoot\..\AzureBakery" -Force


$ErrorActionPreference = "Stop"


Describe "Azure Bakery" {
    try {

        # create and configure resources
        $storageName = ("images$(New-Guid)" -replace "[^A-z0-9]").Substring(0, 24)
        $vmName = ("testvm$(New-Guid)" -replace "[^A-z0-9]").Substring(0, 24)
        $location = "East US"
        $storageName, $vmName | % {New-AzureRmResourceGroup -Name $_ -Location $location}
        New-AzureRmStorageAccount -ResourceGroupName $storageName -Name $storageName -SkuName Standard_LRS -Location $location

        # configure storage
        $context = (Get-AzureRmStorageAccount -ResourceGroupName $storageName).Context
        "images", "artifacts" | % {New-AzureStorageContainer -Name $_ -Context $context}

        # upload cse
        Set-AzureStorageBlobContent `
            -File "$PSScriptRoot\cse.ps1" `
            -Container "artifacts" `
            -Blob "cse.ps1" `
            -Context $context `
            | Out-Null
        $sasToken = New-AzureStorageContainerSASToken `
            -Name "artifacts" `
            -Permission "r" `
            -StartTime (Get-Date) `
            -ExpiryTime (Get-Date).AddHours(2) `
            -Context $context

        $vhdUrl = New-BakedImage `
            -StorageContext $context `
            -WindowsFeature "Web-Server", "Web-Asp-Net"

        It "Creates a VM image" {
            $vhdUrl | Should -BeLike "https://*.blob.core.windows.net/images/BakedWindows.*.vhd"
        }

        It "Can use the VM image" {
            $deployment = New-AzureRmResourceGroupDeployment `
                -Name ((Get-Date -Format "s") -replace "[^\d]") `
                -ResourceGroupName $vmName `
                -TemplateFile "$PSScriptRoot\template.json" `
                -CseUrl "$($context.BlobEndPoint)artifacts/cse.ps1$sasToken" `
                -VhdUrl $vhdUrl `
                -Verbose
            $deployment.Outputs['success'] | Should -Be $true
        }

    } finally {

        # cleanup resources created by the test
        $storageName, $vmName | % {Remove-AzureRmResourceGroup -Name $_ -Force}

    }
}

