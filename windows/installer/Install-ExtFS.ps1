# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$serviceName = 'ExtFS'
$installRoot = Join-Path $env:ProgramFiles 'ExtFS'
$driverSource = Join-Path $PSScriptRoot 'extfs.sys'
$certificateSource = Join-Path $PSScriptRoot 'extfs-test.cer'
$driverDestination = Join-Path $env:SystemRoot 'System32\drivers\extfs.sys'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'ExtFS Setup must be run as administrator.'
    }
}

function Test-TestSigningEnabled {
    $text = (& bcdedit.exe /enum '{current}' 2>&1 | Out-String)
    return $text -match '(?im)^testsigning\s+Yes\s*$'
}

function Wait-ServiceStopped {
    param([string]$Name, [int]$Attempts = 50)
    for ($i = 0; $i -lt $Attempts; $i++) {
        $text = (& sc.exe query $Name 2>&1 | Out-String)
        $code = $LASTEXITCODE
        if ($code -ne 0 -or $text -match '(?im)^\s*STATE\s*:\s*1\b') {
            return $true
        }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

function Wait-ServiceRemoved {
    param([string]$Name, [int]$Attempts = 50)
    for ($i = 0; $i -lt $Attempts; $i++) {
        & sc.exe query $Name *> $null
        if ($LASTEXITCODE -ne 0) {
            return
        }
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out waiting for the $Name service to be removed."
}

Assert-Administrator

if ([Environment]::Is64BitOperatingSystem -ne $true -or
    $env:PROCESSOR_ARCHITECTURE -notin @('AMD64', 'x86')) {
    throw 'This experimental package supports 64-bit Intel/AMD Windows only.'
}
if (-not (Test-Path -LiteralPath $driverSource) -or
    -not (Test-Path -LiteralPath $certificateSource)) {
    throw 'The driver or its test certificate is missing from the setup folder.'
}

# This checkpoint is test-signed only.  Enabling TESTSIGNING changes Windows
# boot policy, so require the reboot before installing or loading the driver.
if (-not (Test-TestSigningEnabled)) {
    & bcdedit.exe /set testsigning on
    if ($LASTEXITCODE -ne 0) {
        throw @'
Windows refused to enable test signing. In a disposable test VM, disable
Secure Boot in the VM firmware and run ExtFS Setup again. Do not weaken the
boot security of a production computer to test this experimental driver.
'@
    }
    Write-Host 'Windows test signing has been enabled. Restart Windows, then run ExtFS Setup again.'
    exit 3010
}

# Trust only the bundled test certificate, then replace any older ExtFS
# service before copying the new driver image into the system drivers folder.
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Import-Certificate -FilePath $certificateSource `
    -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $certificateSource `
    -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

& sc.exe query $serviceName *> $null
if ($LASTEXITCODE -eq 0) {
    & sc.exe stop $serviceName *> $null
    if (-not (Wait-ServiceStopped -Name $serviceName)) {
        Write-Host @'
ExtFS 0.9.2 is intentionally non-unloadable for the entire boot.
Restart Windows, then run this setup again. This prevents replacing kernel code
while filesystem objects might still reference the loaded driver.
'@
        exit 3010
    }
    & sc.exe delete $serviceName *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "The existing ExtFS service could not be deleted (sc.exe exit $LASTEXITCODE)."
    }
    Wait-ServiceRemoved -Name $serviceName
}

Copy-Item -LiteralPath $driverSource -Destination $driverDestination -Force

# Install ExtFS as an on-demand filesystem service.  Starting it here makes
# installation failures visible immediately instead of deferring them to mount.
& sc.exe create $serviceName type= filesys start= demand error= normal `
    binPath= '\SystemRoot\System32\drivers\extfs.sys' `
    DisplayName= 'ExtFS for Windows (experimental)'
if ($LASTEXITCODE -ne 0) {
    throw "The ExtFS filesystem service could not be created (sc.exe exit $LASTEXITCODE)."
}
& sc.exe description $serviceName `
    'Experimental native ext2/ext3/ext4 filesystem driver with bounded ext2/ext3/ext4 file resize' | Out-Null
& sc.exe start $serviceName
if ($LASTEXITCODE -ne 0) {
    throw @"
Windows installed the files but could not load ExtFS (sc.exe exit $LASTEXITCODE).
Check System event log entries from Service Control Manager and Code Integrity.
"@
}

Write-Host 'ExtFS 0.9.2 loaded. Reconnect or reattach the clean ext test volume.'
