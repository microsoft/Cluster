
Configuration GeneralizedVm {
    Param(
        [Parameter(Mandatory)]
        [string[]]$WindowsFeatures
    )

    Import-DscResource -ModuleName "PSDesiredStateConfiguration"
    Import-DscResource -ModuleName "xWindowsUpdate"

    Node localhost {

        LocalConfigurationManager {
            ActionAfterReboot  = "ContinueConfiguration"
            ConfigurationMode  = "ApplyOnly"
            RebootNodeIfNeeded = $true
        }

        $WindowsFeatures | % {
            WindowsFeature ($_ -replace "[^A-z0-9]+") {
                Name = $_
            }
        }
    
        xWindowsUpdateAgent WindowsUpdate {
            UpdateNow        = $true
            Category         = "Security", "Important"
            Notifications    = "Disabled"
            Source           = "MicrosoftUpdate"
            IsSingleInstance = "yes"
        }

    }

}
