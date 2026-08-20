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

function Invoke-BoundedSignatureVerification {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][string]$File,
        [string]$Catalog,
        [ValidateRange(5, 300)][int]$TimeoutSeconds = 45
    )

    $job = Start-Job -ScriptBlock {
        param($Verifier, $Target, $PackageCatalog)
        if ($PackageCatalog) {
            & $Verifier verify /v /pa /c $PackageCatalog $Target
        } else {
            & $Verifier verify /v /pa $Target
        }
        if ($LASTEXITCODE -ne 0) {
            throw "SignTool verification failed for $Target with exit code $LASTEXITCODE."
        }
    } -ArgumentList $Tool, $File, $Catalog
    try {
        if (-not (Wait-Job -Job $job -Timeout $TimeoutSeconds)) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            throw "Timed out after $TimeoutSeconds seconds verifying $File."
        }
        Receive-Job -Job $job -Wait -ErrorAction Stop
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

& $buildScript -Configuration Release -SkipCodeAnalysis:$SkipCodeAnalysis

$signtool = Find-WindowsKitTool -Name 'signtool.exe'
$inf2cat = Find-WindowsKitTool -Name 'Inf2Cat.exe'
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
        -Subject 'CN=ExtFS 0.9.3 Experimental Test Signing' `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyExportPolicy Exportable -KeyLength 3072 -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears(2)
    Export-Certificate -Cert $cert -FilePath $certificateFile -Force | Out-Null
}

$unsignedDriverHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $driver).Hash
Write-Host "Signing the ExtFS driver with test certificate $($cert.Thumbprint)..."
& $signtool sign /v /fd SHA256 /sha1 $cert.Thumbprint /s My $driver
if ($LASTEXITCODE -ne 0) { throw "SignTool signing failed for $driver with exit code $LASTEXITCODE." }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $driver).Hash -eq $unsignedDriverHash) {
    throw "Signing did not change $driver; refusing to package an unsigned driver."
}

# The catalog must hash the final signed SYS. Regenerate it after embedded
# signing, then sign the catalog itself.
Remove-Item -LiteralPath $catalog -Force
$inf2catOs = '10_X64,10_VB_X64,10_CO_X64,10_NI_X64,10_GE_X64,10_25H2_X64'
& $inf2cat "/driver:$release" "/os:$inf2catOs" /uselocaltime
if ($LASTEXITCODE -ne 0) { throw "Inf2Cat regeneration failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath $catalog)) { throw "Inf2Cat did not regenerate $catalog." }

$unsignedCatalogHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $catalog).Hash
Write-Host "Signing the regenerated ExtFS catalog..."
& $signtool sign /v /fd SHA256 /sha1 $cert.Thumbprint /s My $catalog
if ($LASTEXITCODE -ne 0) { throw "SignTool signing failed for $catalog with exit code $LASTEXITCODE." }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $catalog).Hash -eq $unsignedCatalogHash) {
    throw "Signing did not change $catalog; refusing to package an unsigned catalog."
}

# Add temporary trust using the .NET certificate store API. The previous
# Import-Certificate call could block indefinitely on a headless runner.
$rootStore = [Security.Cryptography.X509Certificates.X509Store]::new(
    [Security.Cryptography.X509Certificates.StoreName]::Root,
    [Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
$addedRoot = $false
try {
    $rootStore.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $existingRoots = $rootStore.Certificates.Find(
        [Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
        $cert.Thumbprint, $false)
    if ($existingRoots.Count -eq 0) {
        $rootStore.Add($cert)
        $addedRoot = $true
    }
    foreach ($file in @($driver, $catalog)) {
        Invoke-BoundedSignatureVerification -Tool $signtool -File $file
    }
    Invoke-BoundedSignatureVerification -Tool $signtool -File $driver -Catalog $catalog
    Invoke-BoundedSignatureVerification -Tool $signtool -File $inf -Catalog $catalog
} finally {
    if ($addedRoot) {
        $rootStore.Remove($cert)
    }
    $rootStore.Close()
}

$installerScript = Join-Path $PSScriptRoot 'installer\extfs-installer.nsi'
Push-Location (Split-Path -Parent $installerScript)
try {
    & $makensis $installerScript
    if ($LASTEXITCODE -ne 0) { throw "NSIS failed with exit code $LASTEXITCODE." }
    $setup = Join-Path (Get-Location) 'ExtFS-for-Windows-0.9.3-experimental-x64-setup.exe'
    if (-not (Test-Path -LiteralPath $setup)) { throw 'NSIS did not produce the expected setup file.' }
    Copy-Item -LiteralPath $setup -Destination (Join-Path $root (Split-Path $setup -Leaf)) -Force
} finally {
    Pop-Location
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $driver).Hash
$catHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $catalog).Hash
$reportPath = Join-Path $release 'build-report.txt'
if (Test-Path -LiteralPath $reportPath) {
    Add-Content -LiteralPath $reportPath -Encoding UTF8 -Value @(
        "FinalSignedDriverSHA256: $hash"
        "FinalSignedCatalogSHA256: $catHash"
        "CatalogMembershipVerified: True"
    )
}
Write-Host ''
Write-Host 'Experimental package completed.'
Write-Host "Signed driver SHA-256: $hash"
Write-Host "Signed catalog SHA-256: $catHash"
Write-Host "Setup: $(Join-Path $root 'ExtFS-for-Windows-0.9.3-experimental-x64-setup.exe')"
