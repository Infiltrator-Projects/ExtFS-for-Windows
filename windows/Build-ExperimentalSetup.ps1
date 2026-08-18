# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param(
    [switch]$SkipCodeAnalysis,
    [switch]$KeepExistingTestCertificate
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$release = Join-Path $root 'release\driver'
$driver = Join-Path $release 'extfs.sys'
$inf = Join-Path $release 'extfs.inf'
$catalog = Join-Path $release 'extfs.cat'
$certificateFile = Join-Path $release 'extfs-test.cer'
$buildScript = Join-Path $PSScriptRoot 'Build-And-Validate.ps1'

function Find-WindowsKitTool {
    param([Parameter(Mandatory)][string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
    $candidate = Get-ChildItem -LiteralPath $kits -Filter $Name -File -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object FullName -Match '\\x64\\' |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $candidate) { throw "$Name was not found in the installed Windows Kits." }
    return $candidate.FullName
}

function Find-MakeNSIS {
    $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'NSIS\makensis.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe')
    )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'makensis.exe was not found. Install NSIS to build the setup executable.'
}

& $buildScript -Configuration Release -SkipCodeAnalysis:$SkipCodeAnalysis

$signtool = Find-WindowsKitTool -Name 'signtool.exe'
$makensis = Find-MakeNSIS

foreach ($required in @($driver, $inf, $catalog)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required staged driver-package file is missing: $required" }
}

$cert = $null
if ($KeepExistingTestCertificate -and (Test-Path -LiteralPath $certificateFile)) {
    $fileCert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateFile)
    $cert = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object Thumbprint -eq $fileCert.Thumbprint |
        Select-Object -First 1
    $fileCert.Dispose()
}
if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert `
        -Subject 'CN=ExtFS 0.9.2 Experimental Test Signing' `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyExportPolicy Exportable -KeyLength 3072 -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears(2)
    Export-Certificate -Cert $cert -FilePath $certificateFile -Force | Out-Null
}

Write-Host "Signing the ExtFS driver package with test certificate $($cert.Thumbprint)..."
foreach ($file in @($driver, $catalog)) {
    Write-Host "  Signing $file"
    & $signtool sign /v /fd SHA256 /sha1 $cert.Thumbprint /s My $file
    if ($LASTEXITCODE -ne 0) { throw "SignTool signing failed for $file with exit code $LASTEXITCODE." }
}

# A self-signed development certificate is not normally a trusted root on the
# build host.  Trust its public half in CurrentUser only for verification, then
# remove that temporary trust entry before returning.
$temporaryRoot = $null
try {
    $temporaryRoot = Import-Certificate -FilePath $certificateFile `
        -CertStoreLocation 'Cert:\CurrentUser\Root'
    foreach ($file in @($driver, $catalog)) {
        & $signtool verify /v /pa $file
        if ($LASTEXITCODE -ne 0) { throw "SignTool verification failed for $file with exit code $LASTEXITCODE." }
    }
} finally {
    if ($temporaryRoot) {
        Get-ChildItem Cert:\CurrentUser\Root |
            Where-Object Thumbprint -eq $cert.Thumbprint |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

$installerScript = Join-Path $PSScriptRoot 'installer\extfs-installer.nsi'
Push-Location (Split-Path -Parent $installerScript)
try {
    & $makensis $installerScript
    if ($LASTEXITCODE -ne 0) { throw "NSIS failed with exit code $LASTEXITCODE." }
    $setup = Join-Path (Get-Location) 'ExtFS-for-Windows-0.9.2-experimental-x64-setup.exe'
    if (-not (Test-Path -LiteralPath $setup)) { throw 'NSIS did not produce the expected setup file.' }
    Copy-Item -LiteralPath $setup -Destination (Join-Path $root (Split-Path $setup -Leaf)) -Force
} finally {
    Pop-Location
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $driver).Hash
$catHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $catalog).Hash
Write-Host ''
Write-Host 'Experimental package completed.'
Write-Host "Signed driver SHA-256: $hash"
Write-Host "Signed catalog SHA-256: $catHash"
Write-Host "Setup: $(Join-Path $root 'ExtFS-for-Windows-0.9.2-experimental-x64-setup.exe')"
