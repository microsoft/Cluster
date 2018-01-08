
$VerbosePreference = "Continue"




$obj = Get-Content .\Tests\Definitions\TestSvc.config.json -Raw | ConvertFrom-Json
$hash = $obj | ConvertTo-HashTable0 -Verbose
$hash.Information.Message

