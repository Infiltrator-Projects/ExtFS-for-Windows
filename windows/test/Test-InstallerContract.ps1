# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$installer = Join-Path $root 'windows\installer\Install-ExtFS.ps1'
$nsi = Join-Path $root 'windows\installer\extfs-installer.nsi'
foreach ($path in @($installer, $nsi)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Installer source not found: $path"
    }
}

$text = Get-Content -LiteralPath $installer -Raw
$nsiText = Get-Content -LiteralPath $nsi -Raw
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

# 0.9.4 incorrectly asked .NET for the machine-scoped value of
# PROCESSOR_ARCHITECTURE. That variable is process-scoped and may be absent in
# the machine environment, falsely rejecting a genuine x64 Windows host.
$badArchitectureLookup = "GetEnvironmentVariable('PROCESSOR_ARCHITECTURE', 'Machine')"
if ($text -match [regex]::Escape($badArchitectureLookup) -or
    $nsiText -match [regex]::Escape($badArchitectureLookup)) {
    throw 'Installer still contains the broken machine-scoped PROCESSOR_ARCHITECTURE lookup from 0.9.4.'
}
if ($text -notmatch [regex]::Escape('[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture')) {
    throw 'Installer must use RuntimeInformation.OSArchitecture for native Windows architecture detection.'
}
if ($text -notmatch [regex]::Escape('$env:PROCESSOR_ARCHITEW6432')) {
    throw 'Installer must retain a WOW64-safe native-architecture fallback.'
}
if ($nsiText -match [regex]::Escape('PROCESSOR_ARCHITECTURE')) {
    throw 'NSIS must not perform its own PROCESSOR_ARCHITECTURE architecture gate; PowerShell performs the authoritative OS and PE checks.'
}

Write-Host 'Installer service-path and native-architecture contracts: PASS'
