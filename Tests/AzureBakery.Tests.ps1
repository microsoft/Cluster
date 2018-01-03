

Import-Module .\AzureBakery -Force

Describe "AzureBakery" {

    It "Bakes images" {
        New-BakedImage `
            -ImageResourceGroupName "chkuechimagetest" `
            -WindowsFeature "Web-Server", "Web-Asp-Net"
        Get-AzureStorageBlob `
            -Blob "" `
            -Container "" `
            -Context (Get-AzureRmStorageAccount -ResourceGroupName "").Context
    }

}
