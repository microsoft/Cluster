

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"




<##
 # New cluster set
 #>

function New-ClusterService {
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
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z][A-z0-9]+$")]
        [string]$ServiceName,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z]{3,6}$")]
        [string]$FlightingRingName,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-z][A-z0-9 ]+$")]
        [string]$Region,
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidateNotNullOrEmpty()]
        [ClusterEnvironment]$Environment,
        [ValidateScript( {Test-Script $_} )]
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
    Param(
        [Parameter(Mandatory)]
        [Alias('ServiceName')]
        [string]$Name
    )

    return [ClusterService]::new($Name)
}


function Get-ClusterFlightingRing {
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
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z][A-z0-9]+$")]
        [string]$ServiceName,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-Z]{3,6}$")]
        [string]$FlightingRingName,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [ValidatePattern("^[A-z][A-z0-9 ]+$")]
        [string]$Region,
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidateNotNullOrEmpty()]
        [ClusterEnvironment]$Environment,
        [Parameter(Mandatory, ParameterSetName = 'Components')]
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidateRange(0, 255)]
        [int]$Index
    )

    $id = switch ($PSCmdlet.ParameterSetName) {
        "Components" {"$ServiceName-$FlightingRingName-$Region-$Index"}
        "Object" {"$Environment-$Index"}
    }
    return [Cluster]::new($id)
}


<## 
 # Publish to cluster set
 #>

function Publish-ClusterArtifact {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ClusterResourceGroup]$ClusterSet,
        [Parameter(Mandatory)]
        [ValidateScript( {Test-Script $_} )]
        [string]$Path
    )

    $ClusterSet.UploadArtifact($Path)
    $ClusterSet.PropagateArtifacts()
}


function Publish-ClusterSecret {
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


function New-ClusterImage {
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
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Cluster[]]$Cluster,
        [ValidateScript( {Test-Script $_} )]
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
    Param(
        [string]$ServiceName = "*",
        [string]$FlightingRingName = "*",
        [string]$Region = "*",
        [string]$Index = "*"
    )

    $query = "$Service-$FlightingRing-$Region-$Index"
    return Get-AzureRmResourceGroup `
        | ? {$_.ResourceGroupName -like $query} `
        | % {[Cluster]::new($_.ResourceGroupName)}
}

