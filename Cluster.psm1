

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"




<#
.SYNOPSIS
Creates a ClusterService, ClusterFlightingRing, ClusterEnvironment, or Cluster from a resource group name

.DESCRIPTION
Infers the type of the Cluster node from a resource group name and returns the associated ClusterService, ClusterFlightingRing, ClusterEnvironment, or Cluster object

.PARAMETER ResourceGroupName
Name of the Azure Resource Group name representing a cluster resource group

.EXAMPLE
$MyClusterEnvironment = ConvertTo-ClusterType -ResourceGroupName "MyService-DEV-EastUS"
#>
function ConvertTo-ClusterType {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName
    )

    $height = ($resourceGroupName -split "-").Count
    $type = switch ($height) {
        1 {[ClusterService]}
        2 {[ClusterFlightingRing]}
        3 {[ClusterEnvironment]}
        4 {[Cluster]}
        default {throw "Invalid Cluster resource group name '$resourceGroupName'"}
    }

    return $type::new($resourceGroupName)
}






<#
.SYNOPSIS
Creates a new Service in Azure

.DESCRIPTION
Creates a new Service resource group for Cluster flighting

.PARAMETER Service
Name used to identify the service

.EXAMPLE
New-ClusterService -Service "MyService"

.NOTES
Requires a correctly set AzureRM context
#>
function New-ClusterService {
    Param(
        [Parameter(Mandatory)]
        [string]$Service
    )

    # create and validate new service model and resources
    $clusterService = [ClusterService]@{
        Service = $Service
    }
    if ($clusterService.Exists()) {
        throw "Service '$Service' already exists"
    }
    $clusterService.Create()

    return $clusterService
}



<#
.SYNOPSIS
Creates a new Flighting Ring in Azure

.DESCRIPTION
Creates a new Flighting Ring resource group for Cluster flighting

.PARAMETER Service
Name used to identify the service

.PARAMETER FlightingRing
Name used to identify the flighting ring

.EXAMPLE
New-ClusterFlightingRing -Service "MyService" -FlightingRing "DEV"

.NOTES
Requires a correctly set AzureRM context
#>
function New-ClusterFlightingRing {
    Param(
        [Parameter(Mandatory)]
        [string]$Service,
        [Parameter(Mandatory)]
        [string]$FlightingRing
    )

    # create and validate new flighting ring model and resources
    $clusterFlightingRing = [ClusterFlightingRing]@{
        Service       = $Service
        FlightingRing = $FlightingRing
    }
    if ($clusterFlightingRing.Exists()) {
        throw "Flighting Ring '$clusterFlightingRing' already exists"
    }
    $clusterFlightingRing.Create()

    return $clusterFlightingRing
}



<#
.SYNOPSIS
Creates a new Environment in Azure

.DESCRIPTION
Creates a new Environment resource group for Cluster flighting

.PARAMETER Service
Name used to identify the service

.PARAMETER FlightingRing
Name used to identify the flighting ring

.PARAMETER Region
Name used to identify the region

.EXAMPLE
New-ClusterEnvironnment -Service "MyService" -FlightingRing "DEV" -Region "EastUS"

.NOTES
Requires a correctly set AzureRM context
#>
function New-ClusterEnvironment {
    Param(
        [Parameter(Mandatory)]
        [string]$Service,
        [Parameter(Mandatory)]
        [string]$FlightingRing,
        [Parameter(Mandatory)]
        [string]$Region
    )

    # create and validate flighting ring model
    $clusterFlightingRing = [ClusterFlightingRing]@{
        Service       = $Service
        FlightingRing = $FlightingRing
    }
    if (-not $clusterFlightingRing.Exists()) {
        throw "Flighting Ring '$clusterFlightingRing' does not exist"
    }

    # create and validate new environment model and resources
    $clusterEnvironment = [ClusterEnvironment]@{
        FlightingRing = $clusterFlightingRing
        Region        = $Region
    }
    if ($clusterEnvironment.Exists()) {
        throw "Environment '$clusterEnvironment' already exists"
    }
    $clusterEnvironment.Create()

    return $clusterEnvironment
}


<#
.SYNOPSIS
Creates a new Cluster in Azure

.DESCRIPTION
Long description

.PARAMETER Service
Name used to identify the service

.PARAMETER FlightingRing
Name used to identify the flighting ring

.PARAMETER Region
Name used to identify the region

.EXAMPLE
New-Cluster -Service "MyService" -FlightingRing "DEV" -Region "EastUS"

.NOTES
Requires a correctly set AzureRM context
#>
function New-Cluster {
    Param(
        [Parameter(Mandatory)]
        [string]$Service,
        [Parameter(Mandatory)]
        [string]$FlightingRing,
        [Parameter(Mandatory)]
        [string]$Region
    )

    # create and validate flighting ring model
    $clusterFlightingRing = [ClusterFlightingRing]@{
        Service       = $Service
        FlightingRing = $FlightingRing
    }
    if (-not $clusterFlightingRing.Exists()) {
        throw "Flighting Ring '$clusterFlightingRing' does not exist"
    }

    # create and validate environment model
    $clusterEnvironment = [ClusterEnvironment]@{
        FlightingRing = $clusterFlightingRing
        Region        = $Region
    }
    if (-not $clusterEnvironment.Exists()) {
        throw "Environment '$clusterEnvironment' does not exist"
    }

    # create cluster model and resources
    $cluster = [Cluster]@{
        Environment = $clusterEnvironment
        Index       = $clusterEnvironment.NextIndex()
    }
    $cluster.Create()

    return $cluster
}



function Publish-ClusterArtifact {
    Param(
        [Parameter(Mandatory, ParameterSetName='Object')]
        [Cluster]
        [Parameter(Mandatory, ParameterSetName='Components')]
        [string]$Service,
        [Parameter(Mandatory)]
        [string]$FlightingRing,
        [Parameter(Mandatory)]
        [ValidateScript( {Test-Path $_ -PathType Leaf} )]
        [string]$ArtifactPath,
        [switch]$Sync
    )

    # create and validate flighting ring model
    $clusterFlightingRing = [ClusterFlightingRing]@{
        Service       = $Service
        FlightingRing = $FlightingRing
    }
    if (-not $clusterFlightingRing.Exists()) {
        throw "Flighting Ring '$clusterFlightingRing' does not exist"
    }

    # upload blob to flighting ring
    $clusterFlightingRing.UploadArtifact($ArtifactPath)

    # push to descendents
    if ($Sync) {
        $clusterFlightingRing.PropagateArtifacts()
    }
}


function Publish-ClusterSecret {
    Param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Value,
        [string]$ContentType = "text/plain",
        [switch]$Sync
    )
    
    $vaultName = (Get-AzureRmKeyVault -ResourceGroupName $ResourceGroupName).VaultName
    Set-AzureKeyVaultSecret `
        -VaultName $vaultName `
        -ContentType $ContentType `
        -Name $Name `
        -SecretValue $Value
}


function Publish-ClusterImage {

}


function Publish-ClusterConfiguration {
    Param(

    )
}



<#
.SYNOPSIS
Queries Azure for clusters

.DESCRIPTION
Filters Azure resource groups by the provided parameters and returns the associated Cluster objects.  Supports globs in parameter names.

.PARAMETER Service
Parameter See README for terminology

.PARAMETER FlightingRing
Parameter See README for terminology

.PARAMETER Region
Parameter See README for terminology

.PARAMETER Index
Parameter See README for terminology

.EXAMPLE
An example

#>
function Select-Cluster {
    Param(
        [string]$Service = "*",
        [string]$FlightingRing = "*",
        [string]$Region = "*",
        [string]$Index = "*"
    )

    $query = "$Service-$FlightingRing-$Region-$Index"
    return Get-AzureRmResourceGroup `
        | ? {$_.ResourceGroupName -like $query} `
        | % {[Cluster]::new($_.ResourceGroupName)}
}

