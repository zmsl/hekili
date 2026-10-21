<#
.SYNOPSIS
    Links every addon folder under this repository's src/ into a WoW Forever client's Interface\AddOns.

.DESCRIPTION
    Run from Windows PowerShell against the repository's WSL path, for example:

        powershell -ExecutionPolicy Bypass -File "\\wsl.localhost\personal\home\zack\src\hekili\scripts\Link-Addons.ps1" -WowPath "C:\Program Files (x86)\World of Warcraft\_classic_beta_"

    -WowPath may be the client folder (the one holding Wow.exe or WowB.exe) or its Interface\AddOns folder.
    Each src\<Addon> folder that contains <Addon>.toc gets a directory symbolic link at Interface\AddOns\<Addon>.
    An existing link to the same target is left alone; an existing real folder or a link elsewhere stops the script
    for that addon so nothing is deleted. Directory symbolic links need an elevated prompt or Developer Mode.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $WowPath
)

$ErrorActionPreference = 'Stop'

# The client root and its AddOns folder from either form of the argument.
$full = [System.IO.Path]::GetFullPath($WowPath.TrimEnd('\', '/'))
if ($full -match '(?i)\\Interface\\AddOns$') {
    $root = Split-Path (Split-Path $full -Parent) -Parent
    $addons = $full
} else {
    $root = $full
    $addons = Join-Path $full 'Interface\AddOns'
}

$exe = @('Wow.exe', 'WowB.exe') | Where-Object { Test-Path (Join-Path $root $_) } | Select-Object -First 1
if (-not $exe) {
    throw "No Wow.exe or WowB.exe in '$root'; pass the client folder or its Interface\AddOns folder."
}
if (-not (Test-Path $addons)) {
    New-Item -ItemType Directory -Path $addons | Out-Null
}

# The addon folders: every src\<Name> with a <Name>.toc, from this script's own location in the repository.
$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
if (-not (Test-Path $src)) { throw "No src folder next to this script: '$src'." }
$folders = Get-ChildItem -Path $src -Directory | Where-Object { Test-Path (Join-Path $_.FullName ("$($_.Name).toc")) }
if (-not $folders) { throw "No addon folders (with a TOC) under '$src'." }

Write-Host "Client: $root ($exe)"
Write-Host "AddOns: $addons"
Write-Host "Source: $src"

$failed = 0
foreach ($folder in $folders) {
    $link = Join-Path $addons $folder.Name
    $target = $folder.FullName
    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link -Force
        if ($item.LinkType -eq 'SymbolicLink' -and ($item.Target -join '') -ieq $target) {
            Write-Host "  = $($folder.Name) already linked"
            continue
        }
        if ($item.LinkType) {
            Write-Warning "  ! $($folder.Name) is a $($item.LinkType) to '$($item.Target)'; remove it by hand to relink."
        } else {
            Write-Warning "  ! $($folder.Name) is a real folder at '$link'; move it away to link the repository copy."
        }
        $failed++
        continue
    }
    try {
        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        Write-Host "  + $($folder.Name) -> $target"
    } catch {
        Write-Warning "  ! $($folder.Name): $($_.Exception.Message) (directory symbolic links need an elevated prompt or Developer Mode)"
        $failed++
    }
}

if ($failed -gt 0) { exit 1 }
Write-Host "Done: $($folders.Count) addons linked. Restart the client for a new addon, /reload for edits."
