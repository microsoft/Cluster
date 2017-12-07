

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"


class ClusterEnvironment {
    # naming this 'Environment' causes conflicts with System.Environment

    [ValidatePattern("^[A-Z][A-z0-9]+$")]
    [string]$ServiceName

    [ValidatePattern("^[A-Z]{3,6}$")]
    [string]$FlightingRing

    [ValidatePattern("^[A-Z][A-z0-9]+$")]
    [string]$Region

    ClusterEnvironment([string]$Id) {
        ($this.ServiceName, $this.FlightingRing, $this.Region) = $Id -split "-"
    }

    ClusterEnvironment([string]$ServiceName, [string]$FlightingRing, [string]$Region) {
        $this.ServiceName = $ServiceName
        $this.FlightingRing = $FlightingRing
        $this.Region = $Region
    }

    [string] ToString() {
        return "$($this.ServiceName)-$($this.FlightingRing)-$($this.Region)"
    }

}


class Cluster {

    [ClusterEnvironment]$ClusterEnvironment
    [int]$Index

    Cluster([string]$ServiceName, [string]$FlightingRing, [string]$Region, [int]$Index) {
        $this.ClusterEnvironment = [ClusterEnvironment]::new($ServiceName, $FlightingRing, $Region)
        $this.Index = $Index
    }

    Cluster([ClusterEnvironment]$ClusterEnvironment, [int]$Index) {
        $this.ClusterEnvironment = $ClusterEnvironment
        $this.Index = $Index
    }

    Cluster([string]$Id) {
        ($serviceName, $flightingRing, $region, $this.Index) = $Id -split "-"
        $this.ClusterEnvironment = [ClusterEnvironment]::new($serviceName, $flightingRing, $region)
    }

    [string] ToString() {
        return "$($this.ClusterEnvironment)-$($this.Index)"
    }

}






<#
.SYNOPSIS
Writes formatted execution status messages to the Information stream

.DESCRIPTION
Prepends message lines with execution information and timestamp

.PARAMETER Message
The message(s) logged to the Information stream.  Objects are serialized before writing.

.EXAMPLE
"Hello", "World" | Write-Log

#>
function Write-Log {
    Param(
        [Parameter(ValueFromPipeline)]
        $Message
    )

    begin {
        # 'Write-Log' seemingly nondeterministically appears in the call stack
        $stack = Get-PSCallStack | % {$_.Command} | ? {("<ScriptBlock>", "Write-Log") -notcontains $_}
        if ($stack) {
            [array]::reverse($stack)
            $stack = " | $($stack -join " > ")"
        }
        $timestamp = Get-Date -Format "T"
    }

    process {
        $Message = ($Message | Format-List | Out-String) -split "[\r\n]+" | ? {$_}
        $Message | % {Write-Information "[$timestamp$stack] $_" -InformationAction Continue}
    }

}


function Test-Elevation {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}


function Assert-AzureRmContext {
    Param([string]$Account)

    $ErrorActionPreference = "Stop"

    $contextAccount = (Get-AzureRmContext).Account

    if (-not $contextAccount) {
        Write-Error "Must be logged into Azure.  Run 'Login-AzureRmAccount' before continuing."
    }

    if ($Account -and $contextAccount -ne $Account) {
        Write-Error "Must be logged into Azure as '$Account'.  Run 'Login-AzureRmAccount' before continuing."
    }

    Write-Verbose "Logged into Azure account as '$Account'"
}


function ConvertTo-HashTable {
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject[]]$InputObject
    )

    Process {
        $hash = @{}
        $_.PSObject.Properties | % {$hash[$_.Name] = $_.Value}
        Write-Output $hash
    }
}







<#
.SYNOPSIS
Provisions a new cluster in Azure

.DESCRIPTION
Creates a new resource group and configured storage account, then deploys a template to that resource group

.PARAMETER ServiceName
Parameter See README for terminology

.PARAMETER FlightingRing
Parameter See README for terminology

.PARAMETER Region
Parameter See README for terminology

.EXAMPLE
New-Cluster "OneRF" "PROD" "WestCentralUS"
#>
function New-Cluster {
    [CmdletBinding(DefaultParameterSetName = "Components")]
    Param(
        [Parameter(Mandatory, ParameterSetName = "Components", Position = 0)]
        [string]$ServiceName,
        [Parameter(Mandatory, ParameterSetName = "Components", Position = 1)]
        [string]$FlightingRing,
        [Parameter(Mandatory, ParameterSetName = "Components", Position = 2)]
        [string]$Region,

        [Parameter(Mandatory, ParameterSetName = "ClusterEnvironment", Position = 0)]
        [ClusterEnvironment]$Environment,

        [Parameter(ParameterSetName = "Components", Position = 3)]
        [Parameter(ParameterSetName = "ClusterEnvironment", Position = 1)]
        [ValidateScript( {Test-Path $_ -PathType Container} )]
        [string]$DefinitionsContainer = "$PSScriptRoot\..\..\Definitions"
    )

    Write-Verbose "Parameter validation successful"

    if (-not $ClusterEnvironment) {
        Write-Verbose "Generating ClusterEnvironment object from components"
        $ClusterEnvironment = [ClusterEnvironment]::new($ServiceName, $FlightingRing, $Region)
        Write-Verbose "Created ClusterEnvironment object '$ClusterEnvironment'"
    }

    # get next available ClusterEnvironment index
    Write-Verbose "Finding first unused cluster index"
    [int[]]$indexes = Select-Cluster -ClusterEnvironment $ClusterEnvironment | % {$_.Index}
    for ($index = 0; $indexes -contains $index; $index++) {}
    Write-Verbose "Using cluster index '$index'"

    # generate identifiers
    $cluster = [Cluster]::new($ClusterEnvironment, $index)
    $storageAccountName = "s$(New-Guid)".Replace("-", "").Substring(0, 24)

    # create resources
    Write-Log "Creating resource group '$cluster' and storage account '$storageAccountName'"
    New-AzureRmResourceGroup -Name $cluster -Location $Region | Out-Null
    $storageAccount = New-AzureRmStorageAccount `
        -ResourceGroupName $cluster `
        -Name $storageAccountName `
        -Type "Standard_LRS" `
        -Location $Region `
        -EnableEncryptionService "blob"
    New-AzureStorageContainer -Context $storageAccount.Context -Name "configuration" | Out-Null
    New-AzureStorageContainer -Context $storageAccount.Context -Name "disks" | Out-Null

    # enforce template
    Write-Log "Deploying to cluster '$cluster'"
    New-ClusterDeployment -Cluster $cluster -DefinitionsContainer $DefinitionsContainer

    return $cluster
}


<#
.SYNOPSIS
Starts a template deployment to the specified cluster

.DESCRIPTION
Uses the config selection defined in the README to deploy the most specific template and parameters in \Management\Templates folder to the specified cluster.

.EXAMPLE
New-ClusterDeployment "Contoso" "PROD" "WestCentralUS" 3

.NOTES
Requires the cluster to exist.

#>
function New-ClusterDeployment {
    [CmdletBinding(DefaultParameterSetName = "Components")]
    Param(
        [Parameter(Mandatory, ParameterSetName = "Components", Position = 0)]
        [string]$ServiceName,
        [Parameter(Mandatory, ParameterSetName = "Components", Position = 1)]
        [string]$FlightingRing,
        [Parameter(Mandatory, ParameterSetName = "Components", Position = 2)]
        [string]$Region,
        [Parameter(Mandatory, ParameterSetName = "Components", Position = 3)]
        [int]$Index,

        [Parameter(Mandatory, ParameterSetName = "Cluster", Position = 0)]
        [Cluster]$Cluster,

        [Parameter(ParameterSetName = "Components", Position = 4)]
        [Parameter(ParameterSetName = "Cluster", Position = 1)]
        [ValidateScript( {Test-Path $_ -PathType Container} )]
        [string]$DefinitionsContainer = "."
    )

    Write-Verbose "Parameter validation successful"

    if (-not $Cluster) {
        $Cluster = [Cluster]::new($ServiceName, $FlightingRing, $Region, $Index)
    }

    $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName "$Cluster"
    $storageAccountName = $storageAccount.StorageAccountName
    Write-Verbose "Connected to Storage Account '$storageAccount'"

    # build url components
    Write-Log "Generating secure URL for artifacts"
    $dscUrl = "https://$storageAccountName.blob.core.windows.net/configuration/dsc.zip"
    $vhdContainer = "https://$storageAccountName.blob.core.windows.net/disks/"
    $sasToken = New-AzureStorageContainerSASToken `
        -Context $storageAccount.Context `
        -Container "configuration" `
        -Permission "r" `
        -ExpiryTime ([datetime]::MaxValue)

    # grab the most specific definition of each type
    $selectConfigParams = @{
        ServiceName          = $Cluster.ClusterEnvironment.ServiceName
        FlightingRing        = $Cluster.ClusterEnvironment.FlightingRing
        DefinitionsContainer = $DefinitionsContainer
    }
    $dscFile               = Select-ClusterConfig @selectConfigParams -ConfigType "ps1"
    $templateFile          = Select-ClusterConfig @selectConfigParams -ConfigType "template.json"
    $templateParameterFile = Select-ClusterConfig @selectConfigParams -ConfigType "parameters.json" -ErrorAction "SilentlyContinue"
    $configDataFile        = Select-ClusterConfig @selectConfigParams -ConfigType "config.json" -ErrorAction "SilentlyContinue"
    $dscConfigDataFile     = Select-ClusterConfig @selectConfigParams -ConfigType "psd1" -ErrorAction "SilentlyContinue"

    # package and upload DSC
    Write-Log "Uploading 'Configuration' to '$dscUrl'"
    $publishDscParams = @{
        ConfigurationPath = $dscFile
        OutputArchivePath = "$env:TEMP\dsc.zip"
        Force = $true
    }
    if ($dscConfigDataFile) {
        $publishDscParams["ConfigurationDataPath"] = $dscConfigDataFile
    }
    Publish-AzureRmVMDscConfiguration @publishDscParams
    Set-AzureStorageBlobContent `
        -File "$env:TEMP\dsc.zip" `
        -Container "configuration" `
        -Blob "dsc.zip" `
        -Context $storageAccount.Context `
        -Force `
        | Out-Null
    
    # template deployment parameters
    $deploymentParams = @{
        ResourceGroupName = $Cluster
        TemplateFile      = $templateFile
        DscFileName       = Split-Path -Path $dscFile -Leaf
        DscHash           = (Get-FileHash "$env:TEMP\dsc.zip").Hash.Substring(0, 50)
        DscUrl            = $dscUrl
        Environment       = $cluster.ClusterEnvironment
        VhdContainer      = $vhdContainer
        SasToken          = $sasToken
    }
    if ($templateParameterFile) {
        $deploymentParams["TemplateParameterFile"] = $templateParameterFile
    }
    if ($configDataFile) {
        $deploymentParams["ConfigData"] = Get-Content $configDataFile -Raw | ConvertFrom-Json | ConvertTo-HashTable
    }

    # deploy template
    Write-Log "Starting deployment to '$Cluster'"
    $deploymentName = (Get-Date -Format "s") -replace "[^\d]"
    New-AzureRmResourceGroupDeployment `
        -Name $deploymentName `
        @deploymentParams `
        -Verbose `
        -Force `
        | Write-Log

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
    [CmdletBinding(DefaultParameterSetName = "Query")]
    Param(
        [Parameter(ParameterSetName = "ClusterEnvironment")]
        [ClusterEnvironment]$ClusterEnvironment,

        [Parameter(ParameterSetName = "Query")]
        [string]$ServiceName = "*",
        [Parameter(ParameterSetName = "Query")]
        [string]$FlightingRing = "*",
        [Parameter(ParameterSetName = "Query")]
        [string]$Region = "*",
        [Parameter(ParameterSetName = "Query")]
        [string]$Index = "*"
    )

    $query = switch ([bool]$ClusterEnvironment) {
        $true {"$ClusterEnvironment-*"}
        $false {"$ServiceName-$FlightingRing-$Region-$Index"}
    }

    return Get-AzureRmResourceGroup `
        | ? {$_.ResourceGroupName -like $query} `
        | % {[Cluster]::New($_.ResourceGroupName)}

}


<#
.SYNOPSIS
Selects  (ServiceName, FlightingRing, )

.DESCRIPTION
Long description

.PARAMETER ServiceName
Parameter See README for terminology

.PARAMETER FlightingRing
Parameter See README for terminology

.PARAMETER ConfigType
Parameter See README for terminology

.PARAMETER Container
Parameter See README for terminology

.EXAMPLE
An example

.NOTES
General notes
#>
function Select-ClusterConfig {
    Param(
        [Parameter(Mandatory)]
        [string]$ServiceName,
        [Parameter(Mandatory)]
        [string]$FlightingRing,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigType,
        [ValidateScript( {Test-Path $_ -PathType Container} )]
        [string]$DefinitionsContainer = "."
    )

    $config = $ServiceName, "Default" `
        | % {"$_.$FlightingRing.$Region", "$_.$FlightingRing", $_} `
        | % {"$DefinitionsContainer\$_.$ConfigType"} `
        | ? {Test-Path $_} `
        | Select -First 1

    if ($config) {
        Write-Log "Using $ConfigType '$(Split-Path $config -Leaf)'"
        return $config
    } else {
        Write-Error "No $ConfigType file found"
    }

}
