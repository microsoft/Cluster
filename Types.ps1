<##
 # Types.ps1
 ##
 # Assumptions:
 #   - AzureRM context is initialized
 # Design Considerations:
 #   - Resources with globally unique names are given random IDs and should be accessed by resource group, not name
 #   - Defining a class "Environment" will cause issues with System.Environment
 #>

using namespace Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels
using namespace Microsoft.WindowsAzure.Commands.Common.Storage
using namespace System.Collections

# required for importing types
Import-Module AzureRm

# where region-agnostic resources are defined
$DefaultRegion = "West US 2"

# string preceding a random string on underlying resource names
$DefaultResourcePrefix = "cluster"

# name of the blob storage container containing service artifacts
$ArtifactContainerName = "artifacts"




# abstract
class ClusterResourceGroup {

    [void] Create() {
        if ($this.Exists()) {
            throw "Resource Group '$this' already exists"
        }
        New-AzureRmResourceGroup -Name $this -Location $script:DefaultRegion
        New-AzureRmStorageAccount `
            -ResourceGroupName $this `
            -Name ([ClusterResourceGroup]::NewResourceName()) `
            -Location $script:DefaultRegion `
            -Type "Standard_LRS" `
            -EnableEncryptionService "blob" `
            -EnableHttpsTrafficOnly $true
        New-AzureRmKeyVault `
            -VaultName ([ClusterResourceGroup]::NewResourceName()) `
            -ResourceGroupName $this `
            -Location $script:DefaultRegion
        New-AzureStorageContainer `
            -Context $this.GetStorageContext() `
            -Name $script:ArtifactContainerName
    }

    [bool] Exists() {
        $resourceGroup = Get-AzureRmResourceGroup `
            -ResourceGroupName $this `
            -ErrorAction SilentlyContinue
        return $resourceGroup -as [bool]
    }

    [PSResourceGroup[]] GetChildResourceGroups() {
        return Get-AzureRmResourceGroup `
            | ? {$_.ResourceGroupName -match "^$this-[^-]+$"}
    }

    [LazyAzureStorageContext]$_StorageContext
    [LazyAzureStorageContext] GetStorageContext() {
        if (-not $this._StorageContext) {
            $storageAccount = Get-AzureRmStorageAccount `
                -ResourceGroupName $this
            $this._StorageContext = $storageAccount.Context
        }
        return $this._StorageContext
    }

    [void] NewImage() {
        throw "NYI"
        # TODO: use the chriskuech/AzureBakery repo to create a new VHD
    }

    [void] PropagateArtifacts() {
        $childContexts = $this.GetChildResourceGroups() `
            | % {$_.ResourceGroupName} `
            | % {Get-AzureRmStorageAccount -ResourceGroupName $_} `
            | % {$_.Context}
        $artifactNames = Get-AzureStorageBlob `
            -Container $script:ArtifactContainerName `
            -Context $this.GetStorageContext() `
            | % {$_.Name}
        
        # async start copying blobs
        $pendingBlobs = [ArrayList]::new()
        foreach ($childContext in $childContexts) {
            foreach ($artifactName in $artifactNames) {
                $childBlob = Get-AzureStorageBlob `
                    -Context $childContext `
                    -Container $script:ArtifactContainerName `
                    -Blob $artifactName `
                    -ErrorAction SilentlyContinue
                if (-not $childBlob) {
                    $childBlob = Start-AzureStorageBlobCopy `
                        -Context $this.GetStorageContext() `
                        -DestContext $childContext `
                        -SrcContainer $script:ArtifactContainerName `
                        -DestContainer $script:ArtifactContainerName `
                        -SrcBlob $artifactName `
                        -DestBlob $artifactName
                    $pendingBlobs.Add($childBlob)
                }
            }
        }

        # block until all copies are complete
        foreach ($blob in $pendingBlobs) {
            Get-AzureStorageBlobCopyState `
                -Context $blob.Context `
                -Container $script:ArtifactContainerName `
                -Blob $blob.Name `
                -WaitForComplete
        }
    }

    [void] PropagateBlobs() {
        throw "NYI"
        # TODO: Generalize PropagateArtifacts to support all containers/blobs
        # and deprecate that method
    }

    [void] PropagateSecrets() {
        $keyVaultName = (Get-AzureRmKeyVault -ResourceGroupName $this).VaultName
        $childKeyVaultNames = $this.GetChildResourceGroups() `
            | % {Get-AzureRmKeyVault -ResourceGroupName $_.ResourceGroupName} `
            | % {$_.VaultName}
        $secretNames = (Get-AzureKeyVaultSecret -VaultName $keyVaultName).Name
        foreach ($childKeyVaultName in $childKeyVaultNames) {
            foreach ($secretName in $secretNames) {
                $secretValue = Get-AzureKeyVaultSecret `
                    -VaultName $keyVaultName `
                    -Name $secretName `
                    | % {$_.SecretValue}
                Set-AzureKeyVaultSecret `
                    -VaultName $childKeyVaultName `
                    -Name $secretName `
                    -SecretValue $secretValue
            }
        }
    }

    # abstract
    [string] ToString() {
        throw "This method must be overriden in deriving class"
    }

    [void] UploadArtifact([string] $ArtifactPath) {
        Set-AzureStorageBlobContent `
            -File $ArtifactPath `
            -Container $script:ArtifactContainerName `
            -Blob (Split-Path -Path $ArtifactPath -Leaf) `
            -Context $this.GetStorageContext() `
            -Force
    }

    static [string] NewResourceName() {
        $Length = 24
        $allowedChars = "abcdefghijklmnopqrstuvwxyz0123456789"
        $chars = 1..($Length - $script:DefaultResourcePrefix.Length) `
            | % {Get-Random -Maximum $allowedChars.Length} `
            | % {$allowedChars[$_]}
        return $script:DefaultResourcePrefix + ($chars -join '')
    }
}



class ClusterFlightingRing : ClusterResourceGroup {
    [ValidatePattern("^[A-Z][A-z0-9]+$")]
    [string]$Service

    [ValidatePattern("^[A-Z]{3,6}$")]
    [string]$FlightingRing

    [ClusterEnvironment[]] GetClusterEnvironments() {
        return $this.GetChildResourceGroups() | % {
            ($a, $b, $region) = $_.ResourceGroupName -split "-"
            [ClusterEnvironment]@{
                FlightingRing = $this
                Region        = $region
            }
        }
    }

    [string] ToString() {
        return "$($this.Service)-$($this.FlightingRing)"
    }

}



class ClusterEnvironment : ClusterResourceGroup {
    [ValidateNotNullOrEmpty()]
    [ClusterFlightingRing]$FlightingRing

    [ValidatePattern("^[A-z][A-z0-9 ]+$")]
    [string]$Region

    [Cluster[]] GetClusters() {
        return $this.GetChildResourceGroups() | % {
            ($a, $b, $c, $index) = $_.ResourceGroupName -split "-"
            [Cluster]@{
                Environment = $this
                Index       = $index
            }
        }
    }

    [Cluster] NewChildCluster() {
        $indexes = $this.GetClusters().Index
        for ($index = 0; $index -in $indexes; $index++) {}
        $cluster = [Cluster]@{
            Environment = $this
            Index       = $index
        }
        $cluster.Create()
        return $cluster
    }

    [string] ToString() {
        return "$($this.FlightingRing)-$($this.Region)"
    }

}



class Cluster : ClusterResourceGroup {
    [ValidateNotNullOrEmpty()]
    [ClusterEnvironment]$Environment

    [ValidateRange(0, 255)]
    [int]$Index

    [void] Create() {
        ($this -as [ClusterResourceGroup]).Create()
        New-AzureStorageContainer `
            -Context $this.GetStorageContext() `
            -Name "configuration"
        New-AzureStorageContainer `
            -Context $this.GetStorageContext() `
            -Name "disks"
    }

    [string] GetConfig([string]$DefinitionsContainer, [string]$FileExtension) {
        $service = $this.Environment.FlightingRing.Service
        $flightingRing = $this.Environment.FlightingRing.FlightingRing
        $region = $this.Environment.Region
        $config = $service, "Default" `
            | % {"$_.$flightingRing.$region", "$_.$flightingRing", $_} `
            | % {"$DefinitionsContainer\$_.$FileExtension"} `
            | ? {Test-Path $_} `
            | Select -First 1
        return $config
    }

    [void] PublishConfiguration([string]$DefinitionsContainer, [datetime]$Expiry) {
        $context = $this.GetStorageContext()

        # build url components
        $vhdContainer = "$($context.BlobEndpoint)disks/"
        $sasToken = New-AzureStorageContainerSASToken `
            -Context $context `
            -Container "configuration" `
            -Permission "r" `
            -ExpiryTime $expiry

        # template deployment parameters
        $deploymentParams = @{
            ResourceGroupName = $this
            TemplateFile      = $this.GetConfig($DefinitionsContainer, "template.json")
            Environment       = $this.Environment
            VhdContainer      = $vhdContainer
            SasToken          = $sasToken
        }

        # package and upload DSC
        $dscFile = $this.GetConfig($DefinitionsContainer, "dsc.ps1")
        if ($dscFile) {
            $publishDscParams = @{
                ConfigurationPath = $dscFile
                OutputArchivePath = "$env:TEMP\dsc.zip"
                Force             = $true
            }
            $dscConfigDataFile = $this.GetConfig($DefinitionsContainer, "dsc.psd1")
            if ($dscConfigDataFile) {
                $publishDscParams["ConfigurationDataPath"] = $dscConfigDataFile
            }
            Publish-AzureRmVMDscConfiguration @publishDscParams
            Set-AzureStorageBlobContent `
                -File "$env:TEMP\dsc.zip" `
                -Container "configuration" `
                -Blob "dsc.zip" `
                -Context $context `
                -Force
            $deploymentParams["DscUrl"] = "$($context.BlobEndpoint)configuration/dsc.zip"
            $deploymentParams["DscFileName"] = Split-Path -Path $dscFile -Leaf
            $deploymentParams["DscHash"] = (Get-FileHash "$env:TEMP\dsc.zip").Hash.Substring(0, 50)
        }

        # package and upload CSE
        $cseFile = $this.GetConfig($DefinitionsContainer, "cse.ps1")
        if ($cseFile) {
            Set-AzureStorageBlobContent `
                -File $cseFile `
                -Container "configuration" `
                -Blob "cse.ps1" `
                -Context $context `
                -Force
            $deploymentParams["CseUrl"] = "$($context.BlobEndPoint)configuration/cse.ps1"
        }

        # template parameters
        $templateParameterFile = $this.GetConfig($DefinitionsContainer, "parameters.json")
        if ($templateParameterFile) {
            $deploymentParams["TemplateParameterFile"] = $templateParameterFile
        }

        # freeform json passed to the DSC
        $configDataFile = $this.GetConfig($DefinitionsContainer, "config.json")
        if ($configDataFile) {
            $deploymentParams["ConfigData"] = Get-Content $configDataFile -Raw | ConvertFrom-Json | ConvertTo-HashTable
        }
    
        # deploy template
        New-AzureRmResourceGroupDeployment `
            -Name ((Get-Date -Format "s") -replace "[^\d]") `
            @deploymentParams `
            -Verbose `
            -Force `
            | Write-Log
    }

    [string] ToString() {
        return "$($this.Environment)-$($this.Index)"
    }

}




