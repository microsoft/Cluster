
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
Param()

$ErrorActionPreference = "Stop"

# required for accessing AzureRm types
Import-Module AzureRm

. "$PSScriptRoot\..\Types.ps1"


$Service = [ClusterService]::new("TestSvc")
$FlightingRing = [ClusterFlightingRing]::new("TestSvc-DEV")
$Environment = [ClusterEnvironment]::new("TestSvc-DEV-WestUS2")




Describe "Cluster types" {

    try {


        Context "Creation" {
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
        }



        
        Context "Uploads and propagation" {

            It "Can upload artifacts" {
                "hello world" > "$env:TEMP\sampleblob.txt"
                ( {$Service.UploadArtifact("$env:TEMP\sampleblob.txt")} ) | Should -Not -Throw
                Get-AzureStorageBlobContent `
                    -Context $Service.GetStorageContext() `
                    -Container $ArtifactContainerName `
                    -Blob "sampleblob.txt" `
                    -Destination "$env:TEMP\sampleblob2.txt" `
                    -Force
                Get-Content "$env:TEMP\sampleblob2.txt" | Should -Be "hello world"
            }

            It "Can propagate artifacts" {
                ( {$Service.PropagateArtifacts()} ) | Should -Not -Throw
                Get-AzureStorageBlobContent `
                    -Context $Environment.GetStorageContext() `
                    -Container $ArtifactContainerName `
                    -Blob "sampleblob.txt" `
                    -Destination "$env:TEMP\sampleblob3.txt" `
                    -Force
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

        }


        Context "Clusters" {

            $configs, $expiry = "$PSScriptRoot\Definitions", (Get-Date).AddHours(2)

            It "Can create a cluster" {
                $cluster0 = $Environment.NewChildCluster()
                $cluster0 | Should -Not -BeNullOrEmpty
                $deployment0 = $cluster0.PublishConfiguration($configs, $expiry)
                $deployment0 | Write-Log
                $deployment0.ProvisioningState | Should -Be "Succeeded"
            }

            It "Can create another cluster" {
                $cluster1 = $Environment.NewChildCluster()
                $cluster1 | Should -Not -BeNullOrEmpty
                $deployment1 = $cluster1.PublishConfiguration($configs, $expiry)
                $deployment1 | Write-Log
                $deployment1.ProvisioningState | Should -Be "Succeeded"
            }

            It "Can redeploy clusters" {
                $deployment0 = $cluster0.PublishConfiguration($configs, $expiry)
                $deployment0.ProvisioningState | Should -Be "Succeeded"
                $deployment1 = $cluster1.PublishConfiguration($configs, $expiry)
                $deployment1.ProvisioningState | Should -Be "Succeeded"
            }

        }

    } finally {

        It "Can be cleaned up" -Skip {
            "sampleblob.txt", "sampleblob2.txt", "sampleblob3.txt" `
                | % {"$env:TEMP\$_"} `
                | ? {Test-Path $_} `
                | % {Remove-Item $_}
            $Service, $FlightingRing, $Environment, $cluster0, $cluster1 `
                | % {Remove-AzureRmResourceGroup -Name $_ -Force -ErrorAction SilentlyContinue} `
                | Out-Null
        }

    }
}
