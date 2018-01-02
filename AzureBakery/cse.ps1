
Remove-DscConfigurationDocument -Stage "Current", "Pending", "Previous"
&"$env:SystemRoot\System32\Sysprep\sysprep.exe" /generalize /shutdown
