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
$DefinitionsContainer = "$PSScriptRoot\Definitions"






Describe "Cluster cmdlets" {

    try {


        # creation
        $service = New-ClusterService -Name $ServiceName
        $flightingRing = New-ClusterFlightingRing -Service $service -Name $FlightingRingName
        $environment = New-ClusterEnvironment -FlightingRing $flightingRing -Region $RegionName

        # artifact/secret upload/propagation
        $artifactContent, $artifactPath = "hello world", "$env:TEMP\sampleblob.txt"
        $artifactContent | Out-File $artifactPath -Force

        # cluster management
        $cluster = New-Cluster -Environment $environment -DefinitionsContainer $DefinitionsContainer


        Context "Creation" {
            It "Can create services" {
                @(Get-AzureRmResourceGroup -Name $service).Count | Should -Be 1
                @(Get-AzureRmStorageAccount -ResourceGroupName $service).Count | Should -Be 1
                @(Get-AzureRmKeyVault -ResourceGroupName $service).Count | Should -Be 1
            }

            It "Can create flighting rings" {
                @(Get-AzureRmResourceGroup -Name $flightingRing).Count | Should -Be 1
                @(Get-AzureRmStorageAccount -ResourceGroupName $flightingRing).Count | Should -Be 1
                @(Get-AzureRmKeyVault -ResourceGroupName $flightingRing).Count | Should -Be 1
            }

            It "Can create environments" {
                @(Get-AzureRmResourceGroup -Name $environment).Count | Should -Be 1
                @(Get-AzureRmStorageAccount -ResourceGroupName $environment).Count | Should -Be 1
                @(Get-AzureRmKeyVault -ResourceGroupName $environment).Count | Should -Be 1
            }
        }



        Context "Uploads and propagation" {
            It "Can upload and automatically propagate artifacts" {
                ( {Publish-ClusterArtifact -ClusterSet $service -Path $artifactPath} ) | Should -Not -Throw
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
                $secretValueSecure = $secretValue | ConvertTo-SecureString -AsPlainText -Force
                ( {Publish-ClusterSecret -ClusterSet $service -Name $secretName -Value $secretValueSecure} ) | Should -Not -Throw
                Get-AzureKeyVaultSecret `
                    -VaultName (Get-AzureRmKeyVault -ResourceGroupName $environment).VaultName `
                    -Name $secretName `
                    | % {$_.SecretValueText} `
                    | Should -Be $secretValue
            }

        }



        Context "Cluster management" {
            It "Can create clusters" {
                @(Get-AzureRmResourceGroup -Name $cluster).Count | Should -Be 1
                @(Get-AzureRmStorageAccount -ResourceGroupName $cluster).Count | Should -Be 1
            }

            It "Can publish new Cluster configurations" {
                ( {Publish-ClusterConfiguration -Cluster $cluster -DefinitionsContainer $DefinitionsContainer} ) | Should -Not -Throw
                @(Get-AzureRmVmss -ResourceGroupName $cluster).Count | Should -Be 1
            }
        }




        Context "Reading" {
            It "Can get services" {
                $gottenService = Get-ClusterService -Name $ServiceName
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
                $gottenCluster = Get-Cluster -Environment $environment -Index 0
                "$gottenCluster" | Should -Be "$cluster"
            }

            It "Can select clusters" {
                $selectedCluster = Select-Cluster -ServiceName $ServiceName
                "$selectedCluster" | Should -Be "$cluster"
            }
        }



    } finally {

        # cleanup
        $service, $flightingRing, $environment, $cluster `
            | ? {$_} `
            | % {Remove-AzureRmResourceGroup -Name $_ -Force} `
            | Out-Null
        "sampleblob.txt", "sampleblob2.txt", "sampleblob3.txt" `
            | % {Remove-Item "$env:TEMP\$_" -ErrorAction SilentlyContinue}

    }
}