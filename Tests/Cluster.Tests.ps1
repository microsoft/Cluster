[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
Param()


$ErrorActionPreference = "Stop"

# required for accessing AzureRm types
Import-Module AzureRm

# import the code for testing
Import-Module "$PSScriptRoot\..\Cluster" -Force



$ServiceName = "TestSvc"
$FlightingRingName = "DEV"
$RegionName = "EastUS"
$DefinitionsContainer = ".\Definitions"






Describe "Cluster cmdlets" {

    try {

        Context "Creation" {
            It "Can create services" {
                $service = New-ClusterService -Name $ServiceName
                @(Get-AzureRmResourceGroup -Name $service).Count | Should -Be 1
                @(Get-AzureRmStorageAccount -ResourceGroupName $service).Count | Should -Be 1
                @(Get-AzureRmKeyVault -ResourceGroupName $service).Count | Should -Be 1
            }

            It "Can create flighting rings" {
                $flightingRing = New-ClusterFlightingRing -Service $service -Name $FlightingRingName
                @(Get-AzureRmResourceGroup -Name $flightingRing).Count | Should -Be 1
                @(Get-AzureRmStorageAccount -ResourceGroupName $flightingRing).Count | Should -Be 1
                @(Get-AzureRmKeyVault -ResourceGroupName $flightingRing).Count | Should -Be 1
            }

            It "Can create environments" {
                $environment = New-ClusterEnvironment -FlightingRing $flightingRing -Region $RegionName
                @(Get-AzureRmResourceGroup -Name $environment).Count | Should -Be 1
                @(Get-AzureRmStorageAccount -ResourceGroupName $environment).Count | Should -Be 1
                @(Get-AzureRmKeyVault -ResourceGroupName $environment).Count | Should -Be 1
            }
        }







        Context "Uploads and propagation" {
            It "Can upload and automatically propagate artifacts" {
                $artifactContent, $artifactPath = "hello world", "$env:TEMP\sampleblob.txt"
                $artifactContent | Out-File $artifactPath -Force
                ( {Publish-ClusterArtifact -ClusterSet $service -ArtifactPath $artifactPath} ) | Should -Not -Throw
                Get-AzureStorageBlobContent `
                    -Context $environment.GetStorageContext() `
                    -Container $ArtifactContainerName `
                    -Blob (Split-Path $artifactPath -Leaf) `
                    -Destination "$env:TEMP\sampleblob1.txt" `
                    -Force
                Get-Content "$env:TEMP\sampleblob1.txt" | Should -Be $artifactContent
            }

            It "Can upload and automatically propagate secrets" {
                $secretName, $secretValue = "mySecret", "myValue"
                ( {Publish-ClusterSecret -ClusterSet $service -Name $secretName -Value $secretValue} ) | Should -Not -Throw
                Get-AzureKeyVaultSecret `
                    -VaultName (Get-AzureRmKeyVault -ResourceGroupName $environment).VaultName `
                    -Name $secretName `
                    | % {$_.SecretValueText} `
                    | Should -Be $secretValue
            }

        }





        Context "Cluster management" {
            It "Can create clusters" {
                $cluster = New-Cluster -Environment $environment -DefinitionsContainer $DefinitionsContainer
                @(Get-AzureRmResourceGroup -Name $cluster).Count | Should -Be 1
                @(Get-AzureRmStorageAccount -ResourceGroupName $cluster).Count | Should -Be 1
                @(Get-AzureRmKeyVault -ResourceGroupName $cluster).Count | Should -Be 1
            }

            It "Can publish new Cluster configurations" {
                ( {Publish-ClusterConfiguration -Cluster $cluster -DefinitionsContainer $DefinitionsContainer} ) | Should -Not -Throw
                @(Get-AzureRmVmss -ResourceGroupName $cluster).Count | Should -Be 1
            }
        }




        Context "Reading" {
            It "Can get services" {
                $gottenService = Get-ClusterService -Service $service
                "$gottenService" | Should -Be "$service"
            } 

            It "Can get flighting rings" {
                $gottenFlightingRing = Get-ClusterFlightingRing -Service $service -Name $FlightingRingName
                "$gottenFlightingRing" | Should -Be "$flightingRing"
            }

            It "Can get environments" {
                $gottenEnvironment = Get-ClusterEnvironment -FlightingRing $flightingRing -Region $RegionName
                "$gottenEnvironment" | Should -Be "$environment"
            }

            It "Can get clusters" {
                $gottenCluster = Get-Cluster -Environment $environment -Region $RegionName
                "$gottenCluster" | Should -Be "$cluster"
            }

            It "Can select clusters" {
                $selectedCluster = Select-Cluster -ServiceName "TestSvc"
                "$selectedCluster" | Should -Be "$cluster"
            }
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