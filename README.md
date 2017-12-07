# This repro is still in active development and is not currently supported by Microsoft


# Cluster
PowerShell module for managing multi-region Azure Virtual Machine Scale Set clusters.


## Usage

    # always get latest until we are out of beta
    Install-Module Cluster -Force
    Import-Module Cluster -Force

    # define a cluster
    $myClusterEnvironmentDef = @{
        ServiceName   = "MyService"
        FlightingRing = "DEV"
        Region        = "East US"
    }

    # specify where your correctly named configs are stored
    #  - See README for info on config naming
    $DefinitionsContainer = ".\Definitions"

    # deploy two clusters under the same environment using
    # two different call signatures
    $myClusters = @()
    $myClusters += New-Cluster `
        -Environment $myClusterEnvironmentDef `
        -DefinitionsContainer $DefinitionsContainer
    $myClusters += New-Cluster `
        @myClusterEnvironmentDef `
        -DefinitionsContainer $DefinitionsContainer

    # push an interative deployment to the two clusters
    $myClusters | % {
        New-ClusterDeployment `
            -Cluster $_ `
            -DefinitionsContainer $DefinitionsContainer
    }



## Terminology

| Term           | Description                                                                   | Isomorphic Identifier example |
|----------------|-------------------------------------------------------------------------------|-------------------------------|
| Cluster        | A single resource group.  The atomic unit of a service.                       | `MyService-DEV-EastUS-1`      |
| Environment    | A set of clusters in a common region sharing a common configuration.          | `MyService-DEV-EastUS`        |
| Flighting Ring | A set of environments sharing a common configuration.                         | `MyService-DEV`               |
| Service        | A set of flighting rings containing various versions of a common application. | `MyService`                   |

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
