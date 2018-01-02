
$ErrorActionPreference = "Stop"

# required for accessing AzureRm types
Import-Module AzureRm

# import the code for testing
Import-Module .\Cluster -Force



$ServiceName = "TestSvc"
$FlightingRingName = "DEV"
$RegionName = "EastUS"
$DefinitionsContainer = ".\Definitions"


Describe "Cluster cmdlets" {

    try {

        It "Can create flighting rings" {
            $flightingRing = New-ClusterFlightingRing `
                -Service $ServiceName `
                -FlightingRing $FlightingRingName
            $flightingRing | Should -Be "$ServiceName-$FlightingRingName"

            @(Get-AzureRmResourceGroup -Name $FlightingRing).Count | Should -Be 1
            @(Get-AzureRmStorageAccount -ResourceGroupName $FlightingRing).Count | Should -Be 1
            @(Get-AzureRmKeyVault -ResourceGroupName $FlightingRing).Count | Should -Be 1
        }

        It "Can upload artifacts" {
            "hello world" > "$env:TEMP\sampleblob.txt"
            Publish-ClusterArtifact `
                -Service $ServiceName `
                -FlightingRing $FlightingRingName `
                -ArtifactPath "$env:TEMP\sampleblob.txt"
            Get-AzureStorageBlobContent `
                -Context $FlightingRing.GetStorageContext() `
                -Container $ArtifactContainerName `
                -Blob "sampleblob.txt" `
                -Destination "$env:TEMP\sampleblob2.txt"
            Get-Content "$env:TEMP\sampleblob2.txt" | Should -Be "hello world"
        }

        It "Can create environments" {
            $Environment = New-ClusterEnvironment `
                -Service $ServiceName `
                -FlightingRing $FlightingRingName `
                -Region $RegionName
            $Environment | Should -Be "$ServiceName-$FlightingRingName-$RegionName"
            @(Get-AzureRmResourceGroup -Name $Environment).Count | Should -Be 1
            @(Get-AzureRmStorageAccount -ResourceGroupName $Environment).Count | Should -Be 1
            @(Get-AzureRmKeyVault -ResourceGroupName $Environment).Count | Should -Be 1
        }

        It "Can propagate artifacts" {
            ( {$FlightingRing.PropagateArtifacts()} ) | Should -Not -Throw
            Get-AzureStorageBlobContent `
                -Context $Environment.GetStorageContext() `
                -Container $ArtifactContainerName `
                -Blob "sampleblob.txt" `
                -Destination "$env:TEMP\sampleblob3.txt"
            Get-Content "$env:TEMP\sampleblob3.txt" | Should -Be "hello world"
        }

        It "Can propagate secrets" {
            Set-AzureKeyVaultSecret `
                -VaultName (Get-AzureRmKeyVault -ResourceGroupName $FlightingRing).VaultName `
                -Name "mySecret" `
                -SecretValue ("myValue" | ConvertTo-SecureString -AsPlainText -Force)
            ( {$FlightingRing.PropagateSecrets()} ) | Should -Not -Throw
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
            $FlightingRing, $Environment `
                | % {Remove-AzureRmResourceGroup -Name $_ -Force -ErrorAction SilentlyContinue} `
                | Out-Null
        }

    }
}