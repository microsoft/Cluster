

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"


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
}


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
}


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
}



function Publish-ClusterArtifact {
    Param(
        [Parameter(Mandatory)]
        [string]$Service,
        [Parameter(Mandatory)]
        [string]$FlightingRing,
        [Parameter(Mandatory)]
        [ValidateScript( {Test-Path $_ -PathType Leaf} )]
        [string]$ArtifactPath
    )

    # create and validate flighting ring model
    $clusterFlightingRing = [ClusterFlightingRing]@{
        Service       = $Service
        FlightingRing = $FlightingRing
    }
    if (-not $clusterFlightingRing.Exists()) {
        throw "Flighting Ring '$clusterFlightingRing' does not exist"
    }

    # upload blob to flighting ring and environments
    $clusterFlightingRing.UploadArtifact($ArtifactPath)
    $clusterFlightingRing.PropagateArtifacts()
}


function Publish-ClusterEnvironmentConfiguration {

}


function Publish-ClusterConfiguration {

}



<#
.SYNOPSIS
Queries Azure for clusters

.DESCRIPTION
Filters Azure resource groups by the provided parameters and returns the associated Cluster objects.  Supports globs in parameter names.

.PARAMETER ServiceName
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
        | % {[Cluster]::New($_.ResourceGroupName)}

}

