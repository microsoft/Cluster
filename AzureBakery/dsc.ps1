
Configuration GeneralizedVm {

    Import-DscResource -ModuleName "PSDesiredStateConfiguration"
    Import-DscResource -ModuleName "xWindowsUpdate"

    Node localhost {

        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
        }

        Get-Content ".\WindowsFeatures.txt" | % {
            WindowsFeature ($_ -replace "[^A-z0-9]") {
                Name = $_
            }
        }
    
        xWindowsUpdateAgent WindowsUpdate {
            UpdateNow        = $true
            Category         = "Optional"
            Notifications    = "Disabled"
            Source           = "MicrosoftUpdate"
            IsSingleInstance = "yes"
        }

    }

}
