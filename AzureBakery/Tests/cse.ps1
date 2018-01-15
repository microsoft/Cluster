
$criteria = "Type='software' and IsAssigned=1 and IsHidden=0 and IsInstalled=0"
$searcher = (New-Object -COM Microsoft.Update.Session).CreateUpdateSearcher()


if ($searcher.Search($criteria).Updates | ? IsMandatory) {
    throw "VM is not up to date"
}

if (-not (Get-WindowsFeature "Web-Server" | ? Installed)) {
    throw "Windows feature is not installed"
}
