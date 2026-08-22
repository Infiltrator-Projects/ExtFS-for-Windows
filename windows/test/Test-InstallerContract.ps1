# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$installer = Join-Path $root 'windows\installer\Install-ExtFS.ps1'
$nsi = Join-Path $root 'windows\installer\extfs-installer.nsi'
foreach ($path in @($installer, $nsi)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Installer source not found: $path" }
}

$text = Get-Content -LiteralPath $installer -Raw
$nsiText = Get-Content -LiteralPath $nsi -Raw
$expectedAssignment = "`$serviceImagePath = '\SystemRoot\System32\drivers\extfs.sys'"
$badAssignment = "`$serviceImagePath = '\\SystemRoot\\System32\\drivers\\extfs.sys'"

if ($text -notmatch [regex]::Escape($expectedAssignment)) { throw 'Install-ExtFS.ps1 must use the single-backslash NT service ImagePath.' }
if ($text -match [regex]::Escape($badAssignment)) { throw 'Installer contains the invalid doubled-backslash kernel ImagePath.' }
if ($text -notmatch [regex]::Escape('binPath= $serviceImagePath')) { throw 'sc.exe create must consume the validated $serviceImagePath variable.' }
if ($text -notmatch [regex]::Escape("group= 'File System'")) { throw 'Filesystem service creation must retain the File System load-order group.' }
if ($text -notmatch [regex]::Escape('Get-ItemProperty -LiteralPath $serviceRegistryPath')) { throw 'Installer must validate the actual service registry contract before StartService.' }

$badArchitectureLookup = "GetEnvironmentVariable('PROCESSOR_ARCHITECTURE', 'Machine')"
if ($text -match [regex]::Escape($badArchitectureLookup) -or $nsiText -match [regex]::Escape($badArchitectureLookup)) { throw 'Installer still contains the broken machine-scoped architecture lookup.' }
if ($text -notmatch [regex]::Escape('[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture')) { throw 'Installer must use RuntimeInformation.OSArchitecture.' }
if ($text -notmatch [regex]::Escape('$env:PROCESSOR_ARCHITEW6432')) { throw 'Installer must retain a WOW64-safe fallback.' }
if ($nsiText -match '(?im)^\s*nsExec::ExecToStack.*PROCESSOR_ARCHITECTURE') { throw 'NSIS must not execute its own PROCESSOR_ARCHITECTURE gate.' }

# 0.9.5 incorrectly turned any Windows/CBS/Update pending restart into a fatal
# preflight. 0.9.6 must hard-block only ExtFS-specific pending work and an
# ExtFS-requested test-signing reboot, while unrelated restart state is advisory.
if ($text -match 'function\s+Test-PendingRestart') { throw 'Broad Test-PendingRestart gate from 0.9.5 must not return.' }
if ($text -match [regex]::Escape("throw 'Windows has a pending restart.")) { throw 'Generic pending-restart failures must not return.' }
foreach ($required in @('Get-ExtFsPendingFileOperations','Test-ExtFsRequestedRestartPending','TestSigningRequestedBoot','Write-UnrelatedRestartAdvisory')) {
    if ($text -notmatch [regex]::Escape($required)) { throw "Missing 0.9.6 reboot contract: $required" }
}
if ($text -notmatch [regex]::Escape('Windows has an ExtFS-specific pending file replacement')) { throw 'ExtFS-specific pending replacements must remain a hard blocker.' }
if ($text -notmatch [regex]::Escape('ExtFS enabled Windows test-signing during this boot')) { throw 'ExtFS-requested test-signing reboot must remain a hard blocker.' }
if ($text -notmatch [regex]::Escape('does not treat unrelated restart flags as a hard blocker')) { throw 'Unrelated Windows restart state must be advisory.' }

Write-Host 'Installer service-path, architecture, and reboot contracts: PASS'
