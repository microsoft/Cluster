
Configuration Main {
    Param(
        $Environment,
        $ConfigJson,
        $ServicePrincipalTenantId,
        $ServicePrincipal
    )

    $ConfigData = $ConfigJson | ConvertFrom-Json

    Import-DscResource -ModuleName "PSDesiredStateConfiguration" -Name "Log"

    "[$(Get-Date)] $($ConfigData.Information.Message)" >> "C:\dsc.txt"
    "[$(Get-Date)] $($ConfigData.Information.Message.GetType())" >> "C:\dsc.txt"

    Log HelloWorld {
        Message = $ConfigData.Information.Message
    }
}
