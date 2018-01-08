
Configuration Main {
    Param(
        [string]$Environment,
        [PSObject]$ConfigData,
        [string]$ServicePrincipalTenantId,
        [hashtable]$ServicePrincipal
    )

    Import-DscResource -ModuleName "PSDesiredStateConfiguration" -Name "Log"

    "[$(Get-Date)] $($ConfigData.Information.Message)" >> "C:\dsc.txt"
    "[$(Get-Date)] $($ConfigData.Information.Message.GetType())" >> "C:\dsc.txt"

    Log HelloWorld {
        Message = $ConfigData.Information.Message
    }
}
