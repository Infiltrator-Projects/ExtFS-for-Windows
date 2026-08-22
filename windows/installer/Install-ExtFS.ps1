# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param(
    [ValidateSet('x64', 'ARM64')]
    [string]$TargetArchitecture = 'x64'
)

$ErrorActionPreference = 'Stop'
$packageVersion = '0.9.6'
$serviceName = 'ExtFS'
$installRoot = Join-Path $env:ProgramFiles 'ExtFS'
$driverSource = Join-Path $PSScriptRoot 'extfs.sys'
$certificateSource = Join-Path $PSScriptRoot 'extfs-test.cer'
$driverDestination = Join-Path $env:SystemRoot 'System32\drivers\extfs.sys'
$serviceImagePath = '\SystemRoot\System32\drivers\extfs.sys'
$serviceRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
$stateRegistryPath = 'HKLM:\SOFTWARE\ExtFS'
$testSigningBootMarkerName = 'TestSigningRequestedBoot'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'ExtFS Setup must be run as administrator.'
    }
}

function Test-TestSigningEnabled {
    $text = (& bcdedit.exe /enum '{current}' 2>&1 | Out-String)
    return $text -match '(?im)^testsigning\s+Yes\s*$'
}

function Get-CurrentBootMarker {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $boot = [DateTime]$os.LastBootUpTime
    return $boot.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)
}

function Get-ExtFsPendingFileOperations {
    $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $ops = @((Get-ItemProperty -LiteralPath $sessionManager -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
    return @($ops | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and
        ([string]$_ -match '(?i)(^|[\\/])extfs\.sys($|[\\/])' -or
         [string]$_ -match '(?i)[\\/]ExtFS([\\/]|$)')
    })
}

function Write-UnrelatedRestartAdvisory {
    $reasons = @()
    $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $allFileOps = @((Get-ItemProperty -LiteralPath $sessionManager -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
    if ($allFileOps.Count -gt 0 -and (Get-ExtFsPendingFileOperations).Count -eq 0) {
        $reasons += 'unrelated pending file rename operations'
    }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $reasons += 'Component Based Servicing reports RebootPending'
    }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $reasons += 'Windows Update reports RebootRequired'
    }
    if ($reasons.Count -gt 0) {
        Write-Warning ('Windows has an unrelated pending restart state (' + ($reasons -join '; ') + '). ExtFS 0.9.6 does not treat unrelated restart flags as a hard blocker.')
    }
}

function Test-ExtFsRequestedRestartPending {
    if (-not (Test-Path -LiteralPath $stateRegistryPath)) { return $false }
    $saved = [string](Get-ItemProperty -LiteralPath $stateRegistryPath -Name $testSigningBootMarkerName -ErrorAction SilentlyContinue).$testSigningBootMarkerName
    if ([string]::IsNullOrWhiteSpace($saved)) { return $false }
    $current = Get-CurrentBootMarker
    if ($saved -eq $current) { return $true }
    Remove-ItemProperty -LiteralPath $stateRegistryPath -Name $testSigningBootMarkerName -ErrorAction SilentlyContinue
    return $false
}

function Get-NativeWindowsArchitecture {
    try {
        $runtimeArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToUpperInvariant()
        switch ($runtimeArchitecture) {
            'X64'   { return 'AMD64' }
            'ARM64' { return 'ARM64' }
            'X86'   { return 'x86' }
        }
    } catch {
    }

    $nativeArchitecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($nativeArchitecture)) {
        $nativeArchitecture = $env:PROCESSOR_ARCHITECTURE
    }
    if ([string]::IsNullOrWhiteSpace($nativeArchitecture)) {
        throw 'Windows native architecture could not be determined.'
    }
    return $nativeArchitecture.ToUpperInvariant()
}

function Get-PortableExecutableMachine {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Not a PE image: $Path" }
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "Invalid PE signature: $Path" }
        return $reader.ReadUInt16()
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Wait-ServiceStopped {
    param([string]$Name, [int]$Attempts = 50)
    for ($i = 0; $i -lt $Attempts; $i++) {
        $text = (& sc.exe query $Name 2>&1 | Out-String)
        $code = $LASTEXITCODE
        if ($code -ne 0 -or $text -match '(?im)^\s*STATE\s*:\s*1\b') { return $true }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

function Wait-ServiceRemoved {
    param([string]$Name, [int]$Attempts = 50)
    for ($i = 0; $i -lt $Attempts; $i++) {
        & sc.exe query $Name *> $null
        if ($LASTEXITCODE -ne 0) { return }
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out waiting for the $Name service to be removed."
}

function Get-RecentDriverDiagnostics {
    $lines = @()
    $since = (Get-Date).AddMinutes(-5)
    try {
        $lines += Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = $since } -ErrorAction Stop |
            Select-Object -First 6 |
            ForEach-Object { "SCM $($_.Id): $($_.Message -replace '[\r\n]+', ' ')" }
    } catch {
        $lines += "SCM diagnostics unavailable: $($_.Exception.Message)"
    }
    try {
        $lines += Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = $since } -ErrorAction Stop |
            Select-Object -First 6 |
            ForEach-Object { "CodeIntegrity $($_.Id): $($_.Message -replace '[\r\n]+', ' ')" }
    } catch {
        $lines += "Code Integrity diagnostics unavailable: $($_.Exception.Message)"
    }
    return ($lines -join [Environment]::NewLine)
}

Assert-Administrator

$machineArchitecture = Get-NativeWindowsArchitecture
$expectedMachineArchitecture = if ($TargetArchitecture -eq 'ARM64') { 'ARM64' } else { 'AMD64' }
if ($machineArchitecture -ne $expectedMachineArchitecture) {
    throw "This package targets $TargetArchitecture but Windows reports native architecture $machineArchitecture."
}
if (-not (Test-Path -LiteralPath $driverSource) -or -not (Test-Path -LiteralPath $certificateSource)) {
    throw 'The driver or its test certificate is missing from the setup folder.'
}
$driverMachine = Get-PortableExecutableMachine -Path $driverSource
$expectedDriverMachine = if ($TargetArchitecture -eq 'ARM64') { 0xAA64 } else { 0x8664 }
if ($driverMachine -ne $expectedDriverMachine) {
    throw ('Driver machine mismatch: expected 0x{0:X4}, found 0x{1:X4}.' -f $expectedDriverMachine, $driverMachine)
}

$extfsPendingOps = @(Get-ExtFsPendingFileOperations)
if ($extfsPendingOps.Count -gt 0) {
    throw "Windows has an ExtFS-specific pending file replacement from an earlier install/uninstall. Restart Windows, then run ExtFS Setup again. Pending operation: $($extfsPendingOps[0])"
}
if (Test-ExtFsRequestedRestartPending) {
    throw 'ExtFS enabled Windows test-signing during this boot. Restart Windows once, then run ExtFS Setup again; no driver was installed.'
}
Write-UnrelatedRestartAdvisory

try {
    $secureBootEnabled = Confirm-SecureBootUEFI -ErrorAction Stop
} catch {
    throw "Secure Boot state could not be verified. ExtFS will not weaken boot security or install an experimental driver while this check is unknown. Details: $($_.Exception.Message)"
}
if ($secureBootEnabled) {
    throw 'Secure Boot is enabled. This test-signed driver must not be installed until testing is moved to a disposable system where Secure Boot can be disabled deliberately.'
}

if (-not (Test-TestSigningEnabled)) {
    New-Item -Path $stateRegistryPath -Force | Out-Null
    New-ItemProperty -LiteralPath $stateRegistryPath -Name $testSigningBootMarkerName -Value (Get-CurrentBootMarker) -PropertyType String -Force | Out-Null
    & bcdedit.exe /set testsigning on
    if ($LASTEXITCODE -ne 0) {
        Remove-ItemProperty -LiteralPath $stateRegistryPath -Name $testSigningBootMarkerName -ErrorAction SilentlyContinue
        throw 'Windows refused to enable test signing. Use only a disposable test system; do not weaken a production computer to test this driver.'
    }
    Write-Host 'Windows test signing has been enabled. Restart Windows, then run ExtFS Setup again.'
    exit 3010
}

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Import-Certificate -FilePath $certificateSource -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $certificateSource -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

& sc.exe query $serviceName *> $null
if ($LASTEXITCODE -eq 0) {
    & sc.exe stop $serviceName *> $null
    if (-not (Wait-ServiceStopped -Name $serviceName)) {
        Write-Host "ExtFS $packageVersion is intentionally non-unloadable for the entire boot. Restart Windows, then run this setup again."
        exit 3010
    }
    & sc.exe delete $serviceName *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "The existing ExtFS service could not be deleted (sc.exe exit $LASTEXITCODE)."
    }
    Wait-ServiceRemoved -Name $serviceName
}

Copy-Item -LiteralPath $driverSource -Destination $driverDestination -Force

& sc.exe create $serviceName type= filesys start= demand error= normal binPath= $serviceImagePath group= 'File System' DisplayName= 'ExtFS for Windows (experimental)'
if ($LASTEXITCODE -ne 0) {
    throw "The ExtFS filesystem service could not be created (sc.exe exit $LASTEXITCODE)."
}
& sc.exe description $serviceName 'Experimental native ext2/ext3/ext4 filesystem driver with bounded ext2/ext3/ext4 file resize' | Out-Null

$serviceConfig = Get-ItemProperty -LiteralPath $serviceRegistryPath -ErrorAction Stop
$configuredImagePath = [string]$serviceConfig.ImagePath
if ($configuredImagePath -ne $serviceImagePath) {
    & sc.exe delete $serviceName *> $null
    throw "ExtFS service ImagePath validation failed: expected '$serviceImagePath', found '$configuredImagePath'."
}
if ([int]$serviceConfig.Type -ne 2 -or [int]$serviceConfig.Start -ne 3) {
    & sc.exe delete $serviceName *> $null
    throw "ExtFS service configuration validation failed: expected filesystem Type=2 and demand Start=3; found Type=$($serviceConfig.Type), Start=$($serviceConfig.Start)."
}

$startOutput = (& sc.exe start $serviceName 2>&1 | Out-String).Trim()
$startExit = $LASTEXITCODE
if ($startExit -ne 0) {
    $diagnostics = Get-RecentDriverDiagnostics
    throw @"
Windows installed the files and created ExtFS with the validated image path '$serviceImagePath', but the kernel still refused to load it (sc.exe exit $startExit).

sc.exe output:
$startOutput

Recent driver diagnostics:
$diagnostics
"@
}

Remove-ItemProperty -LiteralPath $stateRegistryPath -Name $testSigningBootMarkerName -ErrorAction SilentlyContinue
Write-Host "ExtFS $packageVersion $TargetArchitecture loaded. Reconnect or reattach the clean, backed-up ext test volume."
