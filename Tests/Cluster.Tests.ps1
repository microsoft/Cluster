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
            It "Can upload artifacts" {
                $artifactContent, $artifactPath = "hello world", "$env:TEMP\sampleblob.txt"
                $artifactContent | Out-File $artifactPath -Force
                ( {Publish-ClusterArtifact -ClusterSet $service -ArtifactPath $artifactPath} ) | Should -Not -Throw
                Get-AzureStorageBlobContent `
                    -Context $service.GetStorageContext() `
                    -Container $ArtifactContainerName `
                    -Blob (Split-Path $artifactPath -Leaf) `
                    -Destination "$env:TEMP\sampleblob2.txt" `
                    -Force
                Get-Content "$env:TEMP\sampleblob2.txt" | Should -Be $artifactContent
            }

            It "Automatically propagates uploaded artifacts" {
                Get-AzureStorageBlobContent `
                    -Context $environment.GetStorageContext() `
                    -Container $ArtifactContainerName `
                    -Blob (Split-Path $artifactPath -Leaf) `
                    -Destination "$env:TEMP\sampleblob3.txt" `
                    -Force
                Get-Content "$env:TEMP\sampleblob3.txt" | Should -Be $artifactContent
            }

            It "Can upload secrets" {
                $secretName, $secretValue = "mySecret", "myValue"
                ( {Publish-ClusterSecret -ClusterSet $service -Name $secretName -Value $secretValue} ) | Should -Not -Throw
                Get-AzureKeyVaultSecret `
                    -VaultName (Get-AzureRmKeyVault -ResourceGroupName $environment).VaultName `
                    -Name "mySecret" `
                    | % {$_.SecretValueText} `
                    | Should -Be "myValue"
            }

            It "Can automatically propagate uploaded secrets" {
                
            }

        }


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