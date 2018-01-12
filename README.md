# Cluster

PowerShell module for managing Azure Resource Manager template deployments

Support for
* Version flighting
* Multiple regions
* Customized images with Windows Features and Updates for fast rollouts
* Support for Desired State Configurations, Custom Script Extensions, and 
* Back-end network isolation (coming)

This module requires PowerShell 5+ and the AzureRM PowerShell module.  This module assumes users are logged into Azure with `Login-AzureRmAccount` or `Import-AzureRmContext` before use.


### Finding Commands
`Get-Command "*-Cluster*"` will list all cmdlets from this module.

`Get-Help "<cmdlet>"` will get the help information for any cmdlets you discover through `Get-Command`.  All cmdlets are described in this README as well.

### Installation
This module is available in the PowerShell Gallery.  PowerShell 5+ is required.  Install with
```PowerShell
Install-Module "Cluster"
```

## Topology
We describe the tree of resource groups that comprise our topology as the *Service Tree*.  Service Trees are defined by Service, Flighting Ring, Environment, and Cluster nodes in the following hierarchy:
```
Service
  L Flighting Ring
      L Environment
          L Cluster
```


### Service Tree nodes

#### Resources
Nodes (Service, Flighting Ring, and Environment) in the "Service Tree" are represented as Azure Resource Groups.  Each resource group contains:
* A Key Vault
* A Storage Account with blob storage containers "images" and "artifacts"

When a node is created, it automatically inherits its parent's secrets and blobs.  This ensures no cross-region dependencies exist in the Cluster (a constraint Azure imposes on ARM template deployments) and optimizes deployment time.


#### IDs
A node's identity is defined as its path through the Service Tree.  For example, given 

```PowerShell
$ServiceName       = "MyService" # the name of a common codebase
$FlightingRingName = "DEV" # the name of a version of the codebase
$RegionName        = "WestUS2" # the name of the Azure region hosting the cluster
```

the resulting IDs are

```PowerShell
$ServiceID       = "$ServiceName"
$FlightingRingID = "$ServiceName-$FlightingRingName"
$EnvironmentID   = "$ServiceName-$FlightingRingName-$RegionName"
```

Cluster IDs are defined by their parent Environment and a unique, automatically assigned the lowest available index.  Ex: 
```PowerShell 
"MyService-DEV-WestUS2-0"
```

Cluster management objects serialize to their ID

```PowerShell
PS C:\> $environment = Get-ClusterEnvironment `
>>          -ServiceName $ServiceName `
>>          -FlightingRingName $FlightingRingName `
>>          -RegionName $RegionName
PS C:\> "$environment"
MyService-DEV-WestUS2
```

#### Creation

Nodes can be created as in the example below.  Each cmdlet creates the node's associated resources in Azure, clones its parent secrets and blobs, and returns a management object that can be used in subsequent commands.

```PowerShell
$service = New-ClusterService -Name $ServiceName
$flightingRing = New-ClusterFlightingRing -Service $service -Name $FlightingRingName
$environment = New-ClusterEnvironment -FlightingRing $flightingRing -Region $RegionName
```


#### Management Objects

Management objects are often returned by Cluster cmdlets.  They expose methods and properties for advanced users (not covered here), but are primarily used to simplify passing parameters, such as in the previous example.

To obtain the managment objects of existing Service Tree nodes, use the following cmdlets:
```PowerShell
$service = Get-ClusterService -Name $ServiceName
$flightingRing = Get-ClusterFlightingRing -Service $service -Name $FlightingRingName
$environment = Get-ClusterEnvironment -FlightingRing $flightingRing -Region $RegionName
```

To obtain a management object without using a management object, use the following cmdlets:
```PowerShell
$service = Get-ClusterService `
    -ServiceName $ServiceName
$flightingRing = Get-ClusterFlightingRing `
    -ServiceName $service `
    -FlightingRingName $FlightingRingName
$environment = Get-ClusterEnvironment `
    -ServiceName $ServiceName`
    -FlightingRingName $FlightingRingName `
    -Region $RegionName
```


#### Flighting (Uploading artifacts and secrets)

Artifacts and secrets can be published to any node and automatically propagated to descendant nodes.
```PowerShell
# upload an artifact to the Service and propagate the artifact to all descendant nodes
Publish-ClusterArtifact -ClusterSet $service -Path ".\sample.txt"

# upload a secret to the Flighting Ring and propagate the secret to all descendant nodes
$secretName = "MySecret"
$secretValue = Read-Host "Enter '$secretName' into this secure prompt"
Publish-ClusterSecret `
    -ClusterSet $flightingRing `
    -Name $secretName `
    -Value $secretValue
```


#### Accessing underlying resources
Cluster management objects serialize to their resource group name, allowing for intuitive integration with the rest of the Azure PowerShell API.  All Azure resources can be obtained by passing in the `-ResourceGroupName $node` to their respective `Get-AzureRm*` cmdlet.  The following example demonstrates how to obtain an Azure Storage Context for integrating with the storage API.  

```PowerShell
$storage = Get-AzureRmStorageAccount -ResourceGroupName $environment
$context = $storage.Context
```

### Clusters

A cluster is a resource group that can independently serve some version of the Service.  A Cluster is a child of an Environment.  

#### Creation
The cmdlet will automatically generate a new unique index for the Cluster, create the standard Service Tree node resources, then publish a *[Configuration](#configurations)* to the Cluster.  
`New-Cluster` follows the same parameter conventions as the other `New-Cluster*` modules with two additional parameters:
* *[DefinitionsContainer](#definitionscontainer)* (default is current location)
* *[Expiry](#expiry)* (default is never)

```PowerShell
$cluster = New-Cluster `
    -Environment $environment `
    -DefinitionsContainer ".\Definitions" `
    -Expiry (Get-Date).AddDays(30)
```

#### Publishing new configurations
Incremental configurations can be pushed using the `Publish-ClusterConfiguration` cmdlet.  **Remove Clusters from traffic before publishing configurations.**  Environments should contain enough Clusters to provide redundancy within an Environment.

```PowerShell
Publish-ClusterConfiguration `
    -Cluster $cluster `
    -DefintionsContainer ".\Definitions" `
    -Expiry (Get-Date).AddDays(30)
```

Cluster objects can be quickly queried using the `Select-Cluster` cmdlet.  The following snippet will update each Cluster under the "MyService-DEV" Flighting Ring.  

```PowerShell
Publish-ClusterConfiguration `
    -Cluster (Select-Cluster $ServiceName $FlightingRingName) `
    -DefinitionsContainer ".\Definitions" `
    -Expiry (Get-Date).AddDays(30)
```


<a name="configurations"></a>

## Configurations
Cluster is designed to fascilitate declarative service management.  Service resources should be defined in Azure Resource Manager templates and, if using Virtual Machines or Virtual Machine Scale Sets, use PowerShell Desired State Configurations to configure the VMs.

Configurations for a service should be stored in a `DefinitionsContainer` and backed up in git.  Within a container, they are selected using the [Config Selection](#configselection) rules.

### Configuration Types

| Config Type             | Extension       | Required |
| ----------------------- | --------------- | -------- |
| ARM Template            | template.json   | Required |
| ARM Template Parameters | parameters.json | Optional |
| PowerShell DSC          | dsc.ps1         | Optional |
| DSC Data file           | dsc.psd1        | Optional |
| Custom Script Extension | cse.ps1         | Optional |
| Generic JSON            | config.json     | Optional |


### Template parameters
Azure Resource Manager Templates used by Cluster must include the following parameters, which will be generated and passed in by `Publish-ClusterConfiguration`.

* **VhdContainer**: URL to the blob storage container containing disks.  Use in the VM or VMSS resource definition in the template.  
  *Must be supported in template*

* **SasToken**: Azure Storage SAS Token for the Cluster Storage Account's "configuration" blob container.  The template should use the SAS token in DSC or CSE extension definitions to download the DSC (`configuration/dsc.zip`) or CSE (`configuration/cse.ps1`).  
  *Must be supported in template*

* **Environment**: Environment ID of the Environment containing this Cluster.  
  *Must be supported in template*

* **DscUrl**: Full URL of the DSC, authenticated with a SAS token.  The template should use this parameter to download the DSC.  
  *Must be supported if and only if a `*.dsc.ps1` file is present* 

* **DscFileName**: Name of the DSC file that will be compiled on the machine.  The template should use this parameter to run the DSC.  
  *Must be supported if and only if a `*.dsc.ps1` file is present*

* **DscHash**: The `ForceUpdateTag` property of the template's DSC extension used to determine if the DSC should run.  
  *Must be supported if and only if a `*.dsc.ps1` file is present*

* **CseUrl**: The SAS token authenticated URL of the Custom Script Extension.  The template should use this parameter to download the Custom Script Extension.  
  *Must be supported if and only if a `*.cse.ps1` file is present*

* **ConfigData**: The JSON object passed to the template as a parameter of type `object`.  The template should use this parameter to pass in Cluster-specific configuration data to the DSC or CSE.  
  *Must be supported if and only if a `*.config.json` file is present*



### Config Selection
Configs are selected...



## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
