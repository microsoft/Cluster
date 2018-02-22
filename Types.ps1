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
Import-Module "AzureRm", "$PSScriptRoot\AzureBakery"







class ClusterResourceGroup {

    # Indentity vector (path through the service tree)
    [string[]]$Identity

    # where region-agnostic resources are defined
    static [string] $DefaultRegion = "West US 2"
        
    # string preceding a random string on underlying resource names
    static [string] $DefaultResourcePrefix = "cluster"

    # name of the blob storage container containing service artifacts
    static [string] $ArtifactContainerName = "artifacts"

    # name of the blob storage container containing VM images
    static [string] $ImageContainerName = "images"

    # underlying property for lazily instantiating Azure Storage Contexts
    hidden [IStorageContext] $_StorageContext



    # create a ClusterResourceGroup model object from its resource group name
    ClusterResourceGroup([string] $resourceGroupName) {
        $this.Identity = $resourceGroupName -split "-"
    }

    # use the values encapsulated in this model object to provision Azure resources
    [void] Create() {
        if ($this.Exists()) {
            throw "Resource Group '$this' already exists"
        }

        # determine if this resource group has a speified region (for Environments and Clusters)
        $region = @{
            $True  = $this.Identity[2]
            $False = [ClusterResourceGroup]::DefaultRegion
        }[$this.Identity.Count -ge 3]

        # create and initialize the Azure resources
        New-AzureRmResourceGroup -Name $this -Location $region
        New-AzureRmStorageAccount `
            -ResourceGroupName $this `
            -Name ([ClusterResourceGroup]::NewResourceName()) `
            -Location $region `
            -Type "Standard_LRS" `
            -EnableEncryptionService "blob" `
            -EnableHttpsTrafficOnly $true
        New-AzureRmKeyVault `
            -VaultName ([ClusterResourceGroup]::NewResourceName()) `
            -ResourceGroupName $this `
            -Location $region
        New-AzureStorageContainer `
            -Context $this.GetStorageContext() `
            -Name ([ClusterResourceGroup]::ArtifactContainerName)
        New-AzureStorageContainer `
            -Context $this.GetStorageContext() `
            -Name ([ClusterResourceGroup]::ImageContainerName)

        # if the resource group has a parent (isn't a 'Service'), propagate assets from parent to this
        $parentId = ($this.Identity | Select -SkipLast 1) -join "-"
        if ($parentId) {
            $parent = [ClusterResourceGroup]::new($parentId)
            $parent.PropagateArtifacts()
            $parent.PropagateImages()
            $parent.PropagateSecrets()
        }
    }


    # returns whether this model's Azure resources have been created
    [bool] Exists() {
        $resourceGroup = Get-AzureRmResourceGroup `
            -ResourceGroupName $this `
            -ErrorAction SilentlyContinue
        return $resourceGroup -as [bool]
    }


    # returns a model for each child service tree node that has been provisioned in Azure
    [ClusterResourceGroup[]] GetChildren() {
        $children = Get-AzureRmResourceGroup `
            | % {$_.ResourceGroupName} `
            | ? {$_ -match "^$this-[^-]+$"} `
            | % {[ClusterResourceGroup]::new($_)}
        return @($children)
    }

    # returns a model for each descendant service tree node (not leaves/Clusters) that has been provisioned in Azure
    [ClusterResourceGroup[]] GetDescendantNodes() {
        $descendants = Get-AzureRmResourceGroup `
            | % {$_.ResourceGroupName} `
            | ? {$_ -like "$this*" -and ($_ -split '-').Count -le 3} `
            | % {[ClusterResourceGroup]::new($_)}
        return @($descendants)
    }

    # lazily instantiates an Azure Storage Context for use with the Azure.Storage module
    [IStorageContext] GetStorageContext() {
        if (-not $this._StorageContext) {
            $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $this
            $this._StorageContext = $storageAccount.Context
        }
        return $this._StorageContext
    }


    # uses the AzureBakery nested module for creating a generalized Windows VHD containing the specified Windows Features
    [void] NewImage([string[]] $WindowsFeature) {
        New-BakedImage `
            -StorageContext $this.GetStorageContext() `
            -WindowsFeature $WindowsFeature `
            -StorageContainer ([ClusterResourceGroup]::ImageContainerName)
    }


    # pushes Artifacts from this service tree node to its descendants
    [void] PropagateArtifacts() {
        $this.PropagateBlobs([ClusterResourceGroup]::ArtifactContainerName)
    }

    # pushes Images from this service tree node to its descendants
    [void] PropagateImages() {
        $this.PropagateBlobs([ClusterResourceGroup]::ImageContainerName)
    }

    # pushes Blobs in the specified container from this service tree node to its descendants
    [void] PropagateBlobs([string] $Container) {
        $descendants = $this.GetDescendantNodes()
        if (-not $descendants) {
            return
        }
        $descendantContexts = $descendants.GetStorageContext()
        $artifactNames = Get-AzureStorageBlob `
            -Container $Container `
            -Context $this.GetStorageContext() `
            | % {$_.Name}
        
        # async start copying blobs
        $pendingBlobs = [ArrayList]::new()
        foreach ($descendantContext in $descendantContexts) {
            foreach ($artifactName in $artifactNames) {
                $descendantBlob = Get-AzureStorageBlob `
                    -Context $descendantContext `
                    -Container $Container `
                    -Blob $artifactName `
                    -ErrorAction SilentlyContinue
                if (-not $descendantBlob) {
                    $descendantBlob = Start-AzureStorageBlobCopy `
                        -Context $this.GetStorageContext() `
                        -DestContext $descendantContext `
                        -SrcContainer $Container `
                        -DestContainer $Container `
                        -SrcBlob $artifactName `
                        -DestBlob $artifactName
                    $pendingBlobs.Add($descendantBlob)
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
    }


    # pushes Azure Key Vault Secrets from this service tree node to its descendants
    [void] PropagateSecrets() {
        $descendants = $this.GetDescendantNodes()
        if (-not $descendants) { 
            return
        }
        $keyVaultName = (Get-AzureRmKeyVault -ResourceGroupName $this).VaultName
        $descendantKeyVaultNames = $descendants `
            | % {Get-AzureRmKeyVault -ResourceGroupName $_} `
            | % {$_.VaultName}
        $secretNames = (Get-AzureKeyVaultSecret -VaultName $keyVaultName).Name
        foreach ($childKeyVaultName in $descendantKeyVaultNames) {
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
    }


    # returns this model's associated resource group name
    [string] ToString() {
        return $this.Identity -join "-"
    }


    # determines the service tree node type (discouraged as it inherently breaks linting)
    [Reflection.TypeInfo] InferType() {
        switch ($this.Identity.Count) {
            1 {return [ClusterService]}
            2 {return [ClusterFlightingRing]}
            3 {return [ClusterEnvironment]}
            4 {return [Cluster]}
        }
        throw "Cannot infer type of '$this'"
        return [void] # return value to not break linting
    }


    # uploads an Artifact (file required for the VM/Container/etc to initialize) to the service tree node
    [void] UploadArtifact([string] $ArtifactPath) {
        Set-AzureStorageBlobContent `
            -File $ArtifactPath `
            -Container ([ClusterResourceGroup]::ArtifactContainerName) `
            -Blob (Split-Path -Path $ArtifactPath -Leaf) `
            -Context $this.GetStorageContext() `
            -Force
    }


    # creates a base36 GUID with a prefix and valid length for creating globally unique Azure resource names
    static [string] NewResourceName() {
        $Length = 24
        $allowedChars = "abcdefghijklmnopqrstuvwxyz0123456789"
        $chars = 1..($Length - [ClusterResourceGroup]::DefaultResourcePrefix.Length) `
            | % {Get-Random -Maximum $allowedChars.Length} `
            | % {$allowedChars[$_]}
        return [ClusterResourceGroup]::DefaultResourcePrefix + ($chars -join '')
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

    # creates a Cluster Azure resource group group that is a child of this model and returns the Cluster's model
    [Cluster] NewChildCluster() {
        $indexes = ($this.GetChildren() | % {[Cluster]::new($_)}).Index # get currently used indexes
        for ($index = 0; $index -in $indexes; $index++) {} # determine lowest available index
        $cluster = [Cluster]::new("$this-$index") # create a Cluster model with the index
        $cluster.Create() # create the Azure resources from the Cluster model
        return $cluster # return the Cluster model
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

    # create a service tree node resource group and resources, with additional Clsuter-specific resources
    [void] Create() {
        New-AzureRmResourceGroup -Name $this -Location $this.Environment.Region
        New-AzureRmStorageAccount `
            -ResourceGroupName $this `
            -Name ([ClusterResourceGroup]::NewResourceName()) `
            -Location $this.Environment.Region `
            -Type "Standard_LRS" `
            -EnableEncryptionService "blob" `
            -EnableHttpsTrafficOnly $true
        New-AzureStorageContainer `
            -Context $this.GetStorageContext() `
            -Name "configuration"
        New-AzureStorageContainer `
            -Context $this.GetStorageContext() `
            -Name "disks"
    }

    # uses the Cluster configuration inheritence model (see README) to identify the most specific config with the specified extension
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
        $configurationSasToken = New-AzureStorageContainerSASToken `
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
            SasToken          = $configurationSasToken
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
        $configJsonFile = $this.GetConfig($DefinitionsContainer, "config.json")
        if ($configJsonFile) {
            $deploymentParams["ConfigJson"] = Get-Content $configJsonFile -Raw
        }

        # baked Windows Image URL (from parent Environment)
        $environmentContext = $this.Environment.GetStorageContext()
        $images = Get-AzureStorageBlob `
            -Context $environmentContext `
            -Container ([ClusterResourceGroup]::ImageContainerName)
        if ($images) {
            $imageName = $images | Sort LastModified -Descending | Select -First 1 | % Name
            $deploymentParams["ImageUrl"] = "$($environmentContext.BlobEndPoint)images/$imageName"
        }

        # deploy template
        $deploymentErrors = $null # redundantly define for linting
        $deployment = New-AzureRmResourceGroupDeployment `
            -Name ((Get-Date -Format "s") -replace "[^\d]") `
            @deploymentParams `
            -Verbose `
            -ErrorVariable deploymentErrors `
            -Force
        if ($deploymentErrors) {
            throw $deploymentErrors
        }
        return $deployment
    }

}




