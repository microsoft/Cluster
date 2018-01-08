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
using namespace Microsoft.Azure.Commands.Common.Authentication.Abstractions
using namespace System.Collections

# required for importing types
Import-Module AzureRm

# where region-agnostic resources are defined
$DefaultRegion = "West US 2"

# string preceding a random string on underlying resource names
$DefaultResourcePrefix = "cluster"

# name of the blob storage container containing service artifacts
$ArtifactContainerName = "artifacts"

# name of the blob storage container containing VM images
$ImageContainerName = "images"





function ConvertTo-HashTable {
    Param(
        [Parameter(ValueFromPipeline)]
        [array]$object
    )

    foreach ($_ in $object) {
        if ($_ -is [PSObject]) {
            $hash = @{}
            $properties = $_.PSObject.Properties | ? {$_.MemberType -eq "NoteProperty"}
            foreach ($p in $properties) {
                $hash[$p.Name] = $p.Value | ConvertTo-HashTable
            }
            Write-Output $hash
        } else {
            Write-Output $_
        }
    }
}






# abstract
class ClusterResourceGroup {

    # Indentity vector
    [string[]]$Identity


    ClusterResourceGroup([string] $resourceGroupName) {
        $this.Identity = $resourceGroupName -split "-"
    }


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
        New-AzureStorageContainer `
            -Context $this.GetStorageContext() `
            -Name $script:ImageContainerName
    }


    [bool] Exists() {
        $resourceGroup = Get-AzureRmResourceGroup `
            -ResourceGroupName $this `
            -ErrorAction SilentlyContinue
        return $resourceGroup -as [bool]
    }


    [ClusterResourceGroup[]] GetChildren() {
        $children = Get-AzureRmResourceGroup `
            | % {$_.ResourceGroupName} `
            | ? {$_ -match "^$this-[^-]+$"} `
            | % {[ClusterResourceGroup]::new($_)}
        return @($children)
    }


    [IStorageContext]$_StorageContext
    [IStorageContext] GetStorageContext() {
        if (-not $this._StorageContext) {
            $storageAccount = Get-AzureRmStorageAccount `
                -ResourceGroupName $this
            $this._StorageContext = $storageAccount.Context
        }
        return $this._StorageContext
    }


    [void] NewImage([string[]] $WindowsFeature) {
        New-BakedImage `
            -Context $this.GetStorageContext() `
            -WindowsFeature $WindowsFeature `
            -StorageContainer $script:ImageContainerName
    }


    [void] PropagateArtifacts() {
        $this.PropagateBlobs($script:ArtifactContainerName)
    }


    [void] PropagateImages() {
        $this.PropagateBlobs($script:ImageContainerName)
    }


    [void] PropagateBlobs([string] $Container) {
        $children = $this.GetChildren()
        if (-not $children) {
            return
        }
        $childContexts = $children.GetStorageContext()
        $artifactNames = Get-AzureStorageBlob `
            -Container $Container `
            -Context $this.GetStorageContext() `
            | % {$_.Name}
        
        # async start copying blobs
        $pendingBlobs = [ArrayList]::new()
        foreach ($childContext in $childContexts) {
            foreach ($artifactName in $artifactNames) {
                $childBlob = Get-AzureStorageBlob `
                    -Context $childContext `
                    -Container $Container `
                    -Blob $artifactName `
                    -ErrorAction SilentlyContinue
                if (-not $childBlob) {
                    $childBlob = Start-AzureStorageBlobCopy `
                        -Context $this.GetStorageContext() `
                        -DestContext $childContext `
                        -SrcContainer $Container `
                        -DestContainer $Container `
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
                -Container $Container `
                -Blob $blob.Name `
                -WaitForComplete
        }

        $children.PropagateBlobs($Container)
    }


    [void] PropagateSecrets() {
        $children = $this.GetChildren()
        if (-not $children) { 
            return
        }
        $keyVaultName = (Get-AzureRmKeyVault -ResourceGroupName $this).VaultName
        $childKeyVaultNames = $children `
            | % {Get-AzureRmKeyVault -ResourceGroupName $_} `
            | % {$_.VaultName}
        $secretNames = (Get-AzureKeyVaultSecret -VaultName $keyVaultName).Name
        foreach ($childKeyVaultName in $childKeyVaultNames) {
            foreach ($secretName in $secretNames) {
                $secret = Get-AzureKeyVaultSecret `
                    -VaultName $keyVaultName `
                    -Name $secretName
                Set-AzureKeyVaultSecret `
                    -VaultName $childKeyVaultName `
                    -Name $secretName `
                    -SecretValue $secret.SecretValue `
                    -ContentType $secret.Attributes.ContentType
            }
        }
        $children.PropagateSecrets()
    }


    # abstract
    [string] ToString() {
        return $this.Identity -join "-"
    }


    [Reflection.TypeInfo] InferType() {
        switch ($this.Identity.Count) {
            1 {return [ClusterService]}
            2 {return [ClusterFlightingRing]}
            3 {return [ClusterEnvironment]}
            4 {return [Cluster]}
        }
        throw "Cannot infer type of '$this'"
        return [void]
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









class ClusterService : ClusterResourceGroup {
    [ValidatePattern("^[A-Z][A-z0-9]+$")]
    [string]$Service

    ClusterService([string] $resourceGroupName) : base($resourceGroupName) {
        $this.Service = $this.Identity
    }

}



class ClusterFlightingRing : ClusterResourceGroup {
    [ValidateNotNullOrEmpty()]
    [ClusterService]$Service

    [ValidatePattern("^[A-Z]{3,6}$")]
    [string]$FlightingRing

    ClusterFlightingRing([string] $resourceGroupName) : base($resourceGroupName) {
        $this.Service = [ClusterService]::new($this.Identity[0])
        $this.FlightingRing = $this.Identity | Select -Last 1
    }

}




class ClusterEnvironment : ClusterResourceGroup {
    [ValidateNotNullOrEmpty()]
    [ClusterFlightingRing]$FlightingRing

    [ValidatePattern("^[A-z][A-z0-9 ]+$")]
    [string]$Region

    ClusterEnvironment([string] $resourceGroupName) : base($resourceGroupName) {
        $this.FlightingRing = [ClusterFlightingRing]::new($this.Identity[0..1] -join "-")
        $this.Region = $this.Identity | Select -Last 1
    }

    [Cluster] NewChildCluster() {
        $indexes = ($this.GetChildren() | % {[Cluster]::new($_)}).Index
        for ($index = 0; $index -in $indexes; $index++) {}
        $cluster = [Cluster]::new("$this-$index")
        $cluster.Create()
        return $cluster
    }

}





class Cluster : ClusterResourceGroup {
    [ValidateNotNullOrEmpty()]
    [ClusterEnvironment]$Environment

    [ValidateRange(0, 255)]
    [int]$Index

    Cluster([string] $resourceGroupName) : base($resourceGroupName) {
        $this.Environment = [ClusterEnvironment]::new($this.Identity[0..2] -join "-")
        $this.Index = $this.Identity | Select -Last 1
    }

    [void] Create() {
        ([ClusterResourceGroup]$this).Create()
        New-AzureStorageContainer `
            -Context $this.GetStorageContext() `
            -Name "configuration"
        New-AzureStorageContainer `
            -Context $this.GetStorageContext() `
            -Name "disks"
    }

    [string] GetConfig([string]$DefinitionsContainer, [string]$FileExtension) {
        ($service, $flightingRing, $region, $index) = $this.Identity
        $config = $service, "Default" `
            | % {"$_.$flightingRing.$region", "$_.$flightingRing", $_} `
            | % {"$DefinitionsContainer\$_.$FileExtension"} `
            | ? {Test-Path $_} `
            | Select -First 1
        return $config
    }


    [PSResourceGroupDeployment] PublishConfiguration([string]$DefinitionsContainer, [datetime]$Expiry) {
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
            $deploymentParams["ConfigData"] = Get-Content $configDataFile -Raw `
                | ConvertFrom-Json `
                | ConvertTo-HashTable
        }
    
        # deploy template
        return New-AzureRmResourceGroupDeployment `
            -Name ((Get-Date -Format "s") -replace "[^\d]") `
            @deploymentParams `
            -Verbose `
            -Force
    }

}




