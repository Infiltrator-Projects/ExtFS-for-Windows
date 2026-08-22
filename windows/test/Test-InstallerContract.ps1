# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$installer = Join-Path $root 'windows\installer\Install-ExtFS.ps1'
if (-not (Test-Path -LiteralPath $installer)) {
    throw "Installer script not found: $installer"
}

$text = Get-Content -LiteralPath $installer -Raw
$expectedAssignment = "`$serviceImagePath = '\SystemRoot\System32\drivers\extfs.sys'"
$badAssignment = "`$serviceImagePath = '\\SystemRoot\\System32\\drivers\\extfs.sys'"

if ($text -notmatch [regex]::Escape($expectedAssignment)) {
    throw "Install-ExtFS.ps1 must define the kernel service ImagePath exactly as \SystemRoot\System32\drivers\extfs.sys."
}
if ($text -match [regex]::Escape($badAssignment)) {
    throw 'Install-ExtFS.ps1 contains the invalid doubled-backslash kernel ImagePath that caused the 0.9.3 StartService failure.'
}
if ($text -notmatch [regex]::Escape('binPath= $serviceImagePath')) {
    throw 'sc.exe create must consume the validated $serviceImagePath variable.'
}
if ($text -notmatch [regex]::Escape("group= 'File System'")) {
    throw 'Filesystem service creation must retain the File System load-order group.'
}
if ($text -notmatch [regex]::Escape('Get-ItemProperty -LiteralPath $serviceRegistryPath')) {
    throw 'Installer must validate the actual service registry contract before attempting StartService.'
}
if ($text -notmatch [regex]::Escape('$configuredImagePath -ne $serviceImagePath')) {
    throw 'Installer must fail closed when the configured service ImagePath differs from the expected NT path.'
}

Write-Host 'Installer service-path contract: PASS'
