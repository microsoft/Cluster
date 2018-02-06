

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"




<##
 # New cluster set
 #>



function New-ClusterService {
    <#
    .SYNOPSIS
    Creates a new Service in Azure and returns the associated ClusterService object
    
    .DESCRIPTION
    Creates a new Service in Azure and returns the associated ClusterService object
    
    .PARAMETER Name
    Name of the Service
    
    .EXAMPLE
    New-ClusterService -Name "MyService"
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory)]
        [ValidatePattern("^[A-Z][A-z0-9]+$")]
        [Alias('ServiceName')]
        [string]$Name
    )

    $service = [ClusterService]::new($Name)
    $service.Create()
    return $service
}


function New-ClusterFlightingRing {
    <#
    .SYNOPSIS
    Creates a new Flighting Ring in Azure and returns the associated ClusterFlightingRing object
    
    .DESCRIPTION
    Creates a new Flighting Ring in Azure and returns the associated ClusterFlightingRing object
    
    .PARAMETER ServiceName
    Name of the Service containg the Flighting Ring
    
    .PARAMETER Service
    ClusterService object of the Service containing the Flighting Ring
    
    .PARAMETER Name
    Name of the Flighting Ring
    
    .EXAMPLE
    # create "MyService-DEV" using names
    New-ClusterFlightingRing -ServiceName "MyService" -FlightingRingName "DEV"

    # create "MyService-DEV" using management objects
    $service = Get-ClusterService -Name "MyService"
    New-ClusterFlightingRing -Service $service -Name "DEV"
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z][A-z0-9]+$")]
        [string]$ServiceName,
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidateNotNullOrEmpty()]
        [ClusterService]$Service,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidatePattern("^[A-Z]{3,6}$")]
        [Alias('FlightingRingName')]
        [string]$Name
    )

    $id = switch ($PSCmdlet.ParameterSetName) {
        "Components" {"$ServiceName-$Name"}
        "Object" {"$Service-$Name"}
    }
    $flightingRing = [ClusterFlightingRing]::new($id)
    $flightingRing.Create()
    return $flightingRing
}


function New-ClusterEnvironment {
    <#
    .SYNOPSIS
    Creates a new Environment in Azure and returns the associated ClusterEnvironment object
    
    .DESCRIPTION
    Creates a new Environment in Azure and returns the associated ClusterEnvironment object
    
    .PARAMETER ServiceName
    Name of the Service containing the Environment
    
    .PARAMETER FlightingRingName
    Name of the Flighting Ring containing the Environment
    
    .PARAMETER FlightingRing
    ClusterFlightingRing object of the Flighting Ring containing the Environment
    
    .PARAMETER Region
    Name of the Region containing the Environment
    
    .EXAMPLE
    # create "MyService-DEV-EastUS" using names
    New-ClusterEnvironment -ServiceName "MyService" -FlightingRingName "DEV" -RegionName "EastUS"

    # create "MyService-DEV-EastUS" using management objects
    $flightingRing = Get-ClusterFlightingRing -ServiceName "MyService" -FlightingRingName "DEV"
    New-ClusterEnvironment -FlightingRing $flightingRing -Region "EastUS"

    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z][A-z0-9]+$")]
        [string]$ServiceName,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z]{3,6}$")]
        [string]$FlightingRingName,
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidateNotNullOrEmpty()]
        [ClusterFlightingRing]$FlightingRing,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidatePattern("^[A-z][A-z0-9 ]+$")]
        [Alias('RegionName')]
        [string]$Region
    )

    $id = switch ($PSCmdlet.ParameterSetName) {
        "Components" {"$ServiceName-$FlightingRingName-$Region"}
        "Object" {"$FlightingRing-$Region"}
    }
    $environment = [ClusterEnvironment]::new($id)
    $environment.Create()
    return $environment
}


function New-Cluster {
    <#
    .SYNOPSIS
    Creates a new Cluster in Azure and returns the associated Cluster object
    
    .DESCRIPTION
    Creates a new Cluster in Azure and returns the associated Cluster object
    
    .PARAMETER ServiceName
    Name of the Service containing the Cluster
    
    .PARAMETER FlightingRingName
    Name of the Flighting Ring containing the Cluster
    
    .PARAMETER RegionName
    Name of the Region containing the Cluster
    
    .PARAMETER Environment
    ClusterEnvironment object of the Flighting Ring containing the Cluster
    
    .PARAMETER DefinitionsContainer
    Path to the folder containing all the configuration definitions
    
    .PARAMETER Expiry
    Date when the configuration can no longer be read from Azure without redeploying
    
    .EXAMPLE
    # create cluster child of "MyService-DEV-EastUS" using names
    New-Cluster -ServiceName "MyService" -FlightingRingName "DEV" -RegionName "EastUS"

    # create "MyService-DEV-EastUS" using management objects
    $environment = Get-ClusterEnvironment -ServiceName "MyService" -FlightingRingName "DEV" -RegionName "EastUS"
    New-Cluster -Environment $environment -DefinitionsContainer ".\Definitions" -Expiry (Get-Date).AddDays(14)
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z][A-z0-9]+$")]
        [string]$ServiceName,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z]{3,6}$")]
        [string]$FlightingRingName,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-z][A-z0-9 ]+$")]
        [Alias('Region')]
        [string]$RegionName,
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidateNotNullOrEmpty()]
        [ClusterEnvironment]$Environment,
        [ValidateScript( {Test-Path $_} )]
        [string]$DefinitionsContainer = (Resolve-Path "."),
        [ValidateNotNullOrEmpty()]
        [datetime]$Expiry = [datetime]::MaxValue
    )

    if (-not $Environment) {
        $Environment = [ClusterEnvironment]::new("$ServiceName-$FlightingRingName-$RegionName")
    }
    $cluster = $Environment.NewChildCluster()
    $cluster.PublishConfiguration($DefinitionsContainer, $Expiry)
    return $cluster
}



<##
 # Get cluster set
 #>

function Get-ClusterService {
    <#
    .SYNOPSIS
    Gets the ClusterService object
    
    .DESCRIPTION
    Gets the ClusterService object
    
    .PARAMETER Name
    Name of the Service
    
    .EXAMPLE
    $service = Get-ClusterService -Name "MyService"
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory)]
        [Alias('ServiceName')]
        [string]$Name
    )

    return [ClusterService]::new($Name)
}


function Get-ClusterFlightingRing {
    <#
    .SYNOPSIS
    Gets the ClusterFlightingRing object
    
    .DESCRIPTION
    Gets the ClusterFlightingRing object
    
    .PARAMETER ServiceName
    Name of the Service containing the Flighting Ring
    
    .PARAMETER Service
    ClusterService object of the Service containing the Flighting Ring
    
    .PARAMETER Name
    Name of the Flighting Ring
    
    .EXAMPLE
    $flightingRing = Get-ClusterFlightingRing -ServiceName "MyService" -FlightingRingName "DEV"
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z][A-z0-9]+$")]
        [string]$ServiceName,
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ClusterService]$Service,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidatePattern("^[A-Z]{3,6}$")]
        [Alias('FlightingRingName')]
        [string]$Name
    )

    $id = switch ($PSCmdlet.ParameterSetName) {
        "Components" {"$ServiceName-$Name"}
        "Object" {"$Service-$Name"}
    }
    return [ClusterFlightingRing]::new($id)
}


function Get-ClusterEnvironment {
    <#
    .SYNOPSIS
    Gets the ClusterEnvironment object
    
    .DESCRIPTION
    Gets the ClusterEnvironment object
    
    .PARAMETER ServiceName
    Name of the Service containing the Environment
    
    .PARAMETER FlightingRingName
    Name of the Flighting Ring containing the Environment
    
    .PARAMETER FlightingRing
    ClusterFlightingRing object of the Flighting Ring containing the Environment
    
    .PARAMETER Region
    Name of the Region containing the Environment
    
    .EXAMPLE
    $environment = Get-ClusterEnvironment -ServiceName "MyService" -FlightingRingName "DEV" -RegionName "EastUS"
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z][A-z0-9]+$")]
        [string]$ServiceName,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z]{3,6}$")]
        [string]$FlightingRingName,
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ClusterFlightingRing]$FlightingRing,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidatePattern("^[A-z][A-z0-9 ]+$")]
        [Alias('RegionName')]
        [string]$Region
    )

    $id = switch ($PSCmdlet.ParameterSetName) {
        "Components" {"$ServiceName-$FlightingRingName-$Region"}
        "Object" {"$FlightingRing-$Region"}
    }
    return [ClusterEnvironment]::new($id)
}


function Get-Cluster {
    <#
    .SYNOPSIS
    Gets the Cluster object
    
    .DESCRIPTION
    Gets the Cluster object
    
    .PARAMETER ServiceName
    Name of the Service containing the Cluster
    
    .PARAMETER FlightingRingName
    Name of the Flighting Ring containing the Cluster
    
    .PARAMETER RegionName
    Name of the Region containing the Cluster
    
    .PARAMETER Environment
    ClusterEnvironment object of the Flighting Ring containing the Cluster
    
    .PARAMETER Index
    Index of the Cluster within its Environment
    
    .EXAMPLE
    $cluster = Get-Cluster -ServiceName "MyService" -FlightingRingName "DEV" -RegionName "EastUS" -Index 0
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z][A-z0-9]+$")]
        [string]$ServiceName,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z]{3,6}$")]
        [string]$FlightingRingName,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-z][A-z0-9 ]+$")]
        [Alias('Region')]
        [string]$RegionName,
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidateNotNullOrEmpty()]
        [ClusterEnvironment]$Environment,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidateRange(0, 255)]
        [int]$Index
    )

    $id = switch ($PSCmdlet.ParameterSetName) {
        "Components" {"$ServiceName-$FlightingRingName-$RegionName-$Index"}
        "Object" {"$Environment-$Index"}
    }
    return [Cluster]::new($id)
}


<## 
 # Publish to cluster set
 #>

function Publish-ClusterArtifact {
    <#
    .SYNOPSIS
    Uploads an artifact to the specified ClusterSet
    
    .DESCRIPTION
    Uploads the artifact to the specified Cluster set and stores it as its name in the "artifacts" container
    
    .PARAMETER ClusterSet
    The Cluster management object representing the subtree of the service that will hold the secret
    
    .PARAMETER Path
    Local path to the artifact to be uploaded
    
    .EXAMPLE
    $flightingRing = Get-ClusterFlightingRing -ServiceName "MyService" -FlightingRingName "DEV"
    Publish-ClusterArtifact -ClusterSet $flightingRing -Path ".\DefinitionsContainer"
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ClusterResourceGroup]$ClusterSet,
        [Parameter(Mandatory)]
        [ValidateScript( {Test-Path $_} )]
        [string]$Path
    )

    $ClusterSet.UploadArtifact($Path)
    $ClusterSet.PropagateArtifacts()
}


function Publish-ClusterSecret {
    <#
    .SYNOPSIS
    Creates a new secret
    
    .DESCRIPTION
    Creates a new Key Vault secret in the specified ClusterSet
    
    .PARAMETER ClusterSet
    The Cluster management object representing the subtree of the service that will hold the secret
    
    .PARAMETER Name
    Name of the secret
    
    .PARAMETER Value
    Value of the secret, represented as a Secure String
    
    .PARAMETER ContentType
    MIME type of the secret
    
    .EXAMPLE
    $flightingRing = Get-ClusterFlightingRing -ServiceName "MyService" -FlightingRingName "DEV"
    $secretName = "MySecret"
    $secretValue = Read-Host "Enter value for '$secretName' in this secure prompt" -AsSecureString
    Publish-ClusterSecret -ClusterSet $flightingRing -Name $secretName -Value $secretValue
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ClusterResourceGroup]$ClusterSet,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [SecureString]$Value,
        [string]$ContentType = "text/plain"
    )

    Set-AzureKeyVaultSecret `
        -VaultName (Get-AzureRmKeyVault -ResourceGroupName $ClusterSet).VaultName `
        -ContentType $ContentType `
        -Name $Name `
        -SecretValue $Value
    $ClusterSet.PropagateSecrets()
}


function Publish-ClusterImage {
    <#
    .SYNOPSIS
    Creates a new baked image
    
    .DESCRIPTION
    Captures a generalized VM image containing the latest Windows Updates and the specified Windows Features
    
    .PARAMETER ClusterSet
    The Cluster management object representing the subtree of the service that will hold the image
    
    .PARAMETER WindowsFeature
    List of Windows Features to be baked into the custom Windows Image
    
    .EXAMPLE
    $flightingRing = Get-ClusterFlightingRing -ServiceName "MyService" -FlightingRingName "DEV"
    Publish-ClusterImage -ClusterSet $flightingRing -WindowsFeature "Web-Server", "Web-Asp-Net45", "Telnet-Client"
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ClusterResourceGroup]$ClusterSet,
        [string[]]$WindowsFeature = @()
    )

    $ClusterSet.NewImage($WindowsFeature)
    $ClusterSet.PropagateImages()
}


function Publish-ClusterConfiguration {
    <#
    .SYNOPSIS
    Pushes a new Resource Manager Template configuration to the Cluster resource group
    
    .DESCRIPTION
    Creates a new Azure Resource Manager Template Deployment, which will ensure the Cluster reflects the template and trigger any Desired State Configuration extensions or Custom Script Extensions in the script.
    
    .PARAMETER Cluster
    The Cluster(s) that will be updated with their new Configurations
    
    .PARAMETER DefinitionsContainer
    Path to the folder containing all the configuration definitions
    
    .PARAMETER Expiry
    Date when the configuration can no longer be read from Azure without redeploying
    
    .EXAMPLE
    $clusters = Select-Cluster "MyService" "DEV" "EastUS"
    Publish-ClusterConfiguration -Cluster $clusters -DefinitionsContainer ".\Definitions" -Expiry (Get-Date).AddDays(14)
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Cluster[]]$Cluster,
        [ValidateScript( {Test-Path $_} )]
        [string]$DefinitionsContainer = (Resolve-Path "."),
        [ValidateNotNullOrEmpty()]
        [datetime]$Expiry = [datetime]::MaxValue
    )

    $Cluster.PublishConfiguration($DefinitionsContainer, $Expiry)
}



<##
 # Utilitiies
 #>

function Select-Cluster {
    <#
    .SYNOPSIS
    Returns an array of Cluster objects matching the parameters
    
    .DESCRIPTION
    Queries the current Azure subscription for 
    
    .PARAMETER ServiceName
    Name (or glob pattern) of the Service containing the Cluster
    
    .PARAMETER FlightingRingName
    Name (or glob pattern) of the Flighting Ring containing the Cluster
    
    .PARAMETER RegionName
    Name (or glob pattern) of the Region containing the Cluster
    
    .PARAMETER Index
    Index (or glob pattern) of the Cluster
    
    .EXAMPLE
    $clusters = Select-Cluster "MyService" "DEV" "EastUS"
    
    .NOTES
    Must be logged into Azure
    #>
    Param(
        [Alias('Service')]
        [string]$ServiceName = "*",
        [Alias('FlightingRing')]
        [string]$FlightingRingName = "*",
        [Alias('Region')]
        [string]$RegionName = "*",
        [string]$Index = "*"
    )

    $query = "$ServiceName-$FlightingRingName-$RegionName-$Index"
    return Get-AzureRmResourceGroup `
        | ? {$_.ResourceGroupName -like $query} `
        | % {[Cluster]::new($_.ResourceGroupName)}
}

