
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
Param()

$ErrorActionPreference = "Stop"

# required for accessing AzureRm types
Import-Module AzureRm

. "$PSScriptRoot\..\Types.ps1"


$Service = [ClusterService]@{
    Service = "TestSvc"
}

$FlightingRing = [ClusterFlightingRing]@{
    Service       = $Service
    FlightingRing = "DEV"
}

$Environment = [ClusterEnvironment]@{
    FlightingRing = $FlightingRing
    Region        = "EastUS"
}



Describe "Cluster types" {

    try {

        <##
         # Component creation
         #>

        It "Can create services" {
            ( {$Service.Create()} ) | Should -Not -Throw
            @(Get-AzureRmResourceGroup -Name $Service).Count | Should -Be 1
            @(Get-AzureRmStorageAccount -ResourceGroupName $Service).Count | Should -Be 1
            @(Get-AzureRmKeyVault -ResourceGroupName $Service).Count | Should -Be 1
        }

        It "Can create flighting rings" {
            ( {$FlightingRing.Create()} ) | Should -Not -Throw
            @(Get-AzureRmResourceGroup -Name $FlightingRing).Count | Should -Be 1
            @(Get-AzureRmStorageAccount -ResourceGroupName $FlightingRing).Count | Should -Be 1
            @(Get-AzureRmKeyVault -ResourceGroupName $FlightingRing).Count | Should -Be 1
        }

        It "Can create environments" {
            ( {$Environment.Create()} ) | Should -Not -Throw
            @(Get-AzureRmResourceGroup -Name $Environment).Count | Should -Be 1
            @(Get-AzureRmStorageAccount -ResourceGroupName $Environment).Count | Should -Be 1
            @(Get-AzureRmKeyVault -ResourceGroupName $Environment).Count | Should -Be 1
        }


        <##
         # Uploads and propagation
         #>

        It "Can upload artifacts" {
            "hello world" > "$env:TEMP\sampleblob.txt"
            ( {$Service.UploadArtifact("$env:TEMP\sampleblob.txt")} ) | Should -Not -Throw
            Get-AzureStorageBlobContent `
                -Context $Service.GetStorageContext() `
                -Container $ArtifactContainerName `
                -Blob "sampleblob.txt" `
                -Destination "$env:TEMP\sampleblob2.txt"
            Get-Content "$env:TEMP\sampleblob2.txt" | Should -Be "hello world"
        }

        It "Can propagate artifacts" {
            ( {$Service.PropagateArtifacts()} ) | Should -Not -Throw
            Get-AzureStorageBlobContent `
                -Context $Environment.GetStorageContext() `
                -Container $ArtifactContainerName `
                -Blob "sampleblob.txt" `
                -Destination "$env:TEMP\sampleblob3.txt"
            Get-Content "$env:TEMP\sampleblob3.txt" | Should -Be "hello world"
        }

        It "Can propagate secrets" {
            Set-AzureKeyVaultSecret `
                -VaultName (Get-AzureRmKeyVault -ResourceGroupName $Service).VaultName `
                -Name "mySecret" `
                -SecretValue ("myValue" | ConvertTo-SecureString -AsPlainText -Force)
            ( {$Service.PropagateSecrets()} ) | Should -Not -Throw
            Get-AzureKeyVaultSecret `
                -VaultName (Get-AzureRmKeyVault -ResourceGroupName $Environment).VaultName `
                -Name "mySecret" `
                | % {$_.SecretValueText} `
                | Should -Be "myValue"
        }

    } finally {

        It "Can be cleaned up" {
            "sampleblob.txt", "sampleblob2.txt", "sampleblob3.txt" `
                | % {Remove-Item "$env:TEMP\$_" -ErrorAction SilentlyContinue}
            $Service, $FlightingRing, $Environment `
                | % {Remove-AzureRmResourceGroup -Name $_ -Force -ErrorAction SilentlyContinue} `
                | Out-Null
        }

    }
}