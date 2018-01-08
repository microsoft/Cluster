

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


