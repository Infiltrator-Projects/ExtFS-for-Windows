# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$SkipCodeAnalysis
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $PSScriptRoot 'driver\extfs.sln'
$project = Join-Path $PSScriptRoot 'driver\extfs.vcxproj'
$inf = Join-Path $PSScriptRoot 'driver\extfs.inf'
$release = Join-Path $root 'release\driver'
$packagesConfig = Join-Path $root 'packages.config'
$packagesDir = Join-Path $root 'packages'
$wdkNuGetVersion = '10.0.28000.2526'

function Find-NuGet {
    $command = Get-Command nuget.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $wingetLink = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\nuget.exe'
    if (Test-Path -LiteralPath $wingetLink) { return $wingetLink }

    throw 'NuGet was not found. Install Microsoft.NuGet (winget install --id Microsoft.NuGet --source winget).'
}


function Enter-VisualStudioDeveloperShell {
    if ($env:VSCMD_VER) {
        Write-Host "Visual Studio Developer Shell already active ($($env:VSCMD_VER))."
        return
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'vswhere.exe was not found. Visual Studio 2017 or later is required.'
    }

    $installation = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
        -property installationPath | Select-Object -First 1
    if (-not $installation) {
        throw 'No Visual Studio installation containing MSBuild was found.'
    }

    $devShellDll = Join-Path $installation 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
    if (-not (Test-Path -LiteralPath $devShellDll)) {
        throw "Visual Studio Developer Shell module was not found: $devShellDll"
    }

    Import-Module $devShellDll
    Enter-VsDevShell -VsInstallPath $installation -SkipAutomaticLocation | Out-Null
    Write-Host "Visual Studio Developer Shell initialised: $installation"
}

function Add-WdkBuildToolsToPath {
    param([Parameter(Mandatory)][string]$RestoredPackages,
          [Parameter(Mandatory)][string]$Version)

    # WDK MSBuild tasks launch helper programs such as StampInf through the
    # process search path.  Prefer the helper from the pinned WDK package so
    # that the executable version matches the headers/targets being built.
    $wdkPackage = Join-Path $RestoredPackages "Microsoft.Windows.WDK.x64.$Version"
    $stampinf = $null
    if (Test-Path -LiteralPath $wdkPackage) {
        $stampinf = Get-ChildItem -LiteralPath $wdkPackage -Filter 'stampinf.exe' -File -Recurse `
            -ErrorAction SilentlyContinue |
            Where-Object FullName -Match '\\x64\\' |
            Sort-Object FullName -Descending |
            Select-Object -First 1
    }

    if (-not $stampinf) {
        $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
        if (Test-Path -LiteralPath $kits) {
            $stampinf = Get-ChildItem -LiteralPath $kits -Filter 'stampinf.exe' -File -Recurse `
                -ErrorAction SilentlyContinue |
                Where-Object FullName -Match '\\x64\\' |
                Sort-Object FullName -Descending |
                Select-Object -First 1
        }
    }

    if (-not $stampinf) {
        throw 'stampinf.exe was not found in either the restored WDK NuGet package or the installed Windows Kits.'
    }

    $toolDirectory = Split-Path -Parent $stampinf.FullName
    $pathEntries = $env:Path -split ';'
    if ($pathEntries -notcontains $toolDirectory) {
        $env:Path = "$toolDirectory;$env:Path"
    }
    Write-Host "WDK build-tool path: $toolDirectory"
    Write-Host "StampInf: $($stampinf.FullName)"
}

function Find-MSBuild {
    $command = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $path = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
            -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
        if ($path) { return $path }
    }
    throw 'MSBuild was not found. Install Visual Studio Build Tools/Visual Studio with the WDK.'
}

function Find-WindowsKitTool {
    param([Parameter(Mandatory)][string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
    if (-not (Test-Path -LiteralPath $kits)) {
        throw "$Name was not found because the Windows 10/11 SDK/WDK tools directory is missing."
    }
    $candidate = Get-ChildItem -LiteralPath $kits -Filter $Name -File -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object FullName -Match '\\x64\\' |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $candidate) { throw "$Name was not found in the installed Windows Kits." }
    return $candidate.FullName
}

$nuget = Find-NuGet
Write-Host "Restoring pinned Microsoft WDK/SDK NuGet packages ($wdkNuGetVersion)..."
& $nuget restore $packagesConfig -PackagesDirectory $packagesDir -NonInteractive
if ($LASTEXITCODE -ne 0) { throw "NuGet restore failed with exit code $LASTEXITCODE." }

$wdkProps = Join-Path $packagesDir "Microsoft.Windows.WDK.x64.$wdkNuGetVersion\build\native\Microsoft.Windows.WDK.x64.props"
if (-not (Test-Path -LiteralPath $wdkProps)) {
    throw "WDK NuGet restore completed but the expected WDK build properties were not found: $wdkProps"
}

# Microsoft's current WDK sample build flow enters the Visual Studio Developer
# Shell for both installed-WDK and NuGet-WDK builds.  This supplies the normal
# compiler/SDK environment expected by WDK MSBuild tasks.  We also expose the
# pinned WDK helper directory explicitly because tasks such as StampInf launch
# their executable through PATH.
Enter-VisualStudioDeveloperShell
Add-WdkBuildToolsToPath -RestoredPackages $packagesDir -Version $wdkNuGetVersion

$msbuild = Find-MSBuild
$infverif = Find-WindowsKitTool -Name 'InfVerif.exe'
$inf2cat = Find-WindowsKitTool -Name 'Inf2Cat.exe'

Write-Host "WDK NuGet props: $wdkProps"
Write-Host "Building ExtFS $Configuration x64 with: $msbuild"
& $msbuild $solution /m /t:Clean,Build "/p:Configuration=$Configuration" /p:Platform=x64
if ($LASTEXITCODE -ne 0) { throw "MSBuild failed with exit code $LASTEXITCODE." }

if (-not $SkipCodeAnalysis) {
    Write-Host 'Running WDK/Visual C++ driver Code Analysis...'
    & $msbuild $project /m "/p:Configuration=$Configuration" /p:Platform=x64 `
        /p:RunCodeAnalysisOnce=True
    if ($LASTEXITCODE -ne 0) { throw "Driver Code Analysis failed with exit code $LASTEXITCODE." }
}

$driverRoot = Join-Path $PSScriptRoot 'driver'
$driver = Get-ChildItem -LiteralPath $driverRoot -Filter extfs.sys -File -Recurse |
    Where-Object FullName -Match "\\$Configuration\\" |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $driver) {
    throw 'The build completed but extfs.sys could not be located under windows\driver.'
}

# StampInf writes the package INF into the configuration output directory.  Stage
# that exact INF rather than the source template so validation/catalog hashing
# describes precisely the files that will be shipped together.
$builtInf = Get-ChildItem -LiteralPath $driverRoot -Filter extfs.inf -File -Recurse |
    Where-Object FullName -Match "\\$Configuration\\" |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $builtInf) {
    throw 'The build completed but the stamped extfs.inf could not be located under windows\driver.'
}

if (Test-Path -LiteralPath $release) {
    Remove-Item -LiteralPath $release -Recurse -Force
}
New-Item -ItemType Directory -Path $release -Force | Out-Null
$stagedDriver = Join-Path $release 'extfs.sys'
$stagedInf = Join-Path $release 'extfs.inf'
$stagedCatalog = Join-Path $release 'extfs.cat'
Copy-Item -LiteralPath $driver.FullName -Destination $stagedDriver -Force
Copy-Item -LiteralPath $builtInf.FullName -Destination $stagedInf -Force

Write-Host 'Running InfVerif in Windows Driver mode against the staged package...'
& $infverif /w /v $stagedInf
if ($LASTEXITCODE -ne 0) { throw "InfVerif failed with exit code $LASTEXITCODE." }

# Generate the catalog explicitly after staging the final SYS and stamped INF.
# This avoids relying on Visual Studio's implicit signing certificate and makes
# the catalog hashes correspond exactly to the package that our setup ships.
$inf2catOs = '10_X64,10_VB_X64,10_CO_X64,10_NI_X64,10_GE_X64,10_25H2_X64'
Write-Host "Generating extfs.cat with Inf2Cat for: $inf2catOs"
& $inf2cat "/driver:$release" "/os:$inf2catOs" /uselocaltime
if ($LASTEXITCODE -ne 0) { throw "Inf2Cat failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath $stagedCatalog)) {
    throw "Inf2Cat completed but did not produce the catalog declared by extfs.inf: $stagedCatalog"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagedDriver).Hash
$catHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagedCatalog).Hash
$report = @(
    "ExtFS Windows build validation"
    "Date: $([DateTime]::Now.ToString('o'))"
    "Configuration: $Configuration"
    "MSBuild: $msbuild"
    "NuGet: $nuget"
    "WDKNuGet: $wdkNuGetVersion"
    "InfVerif: $infverif"
    "Inf2Cat: $inf2cat"
    "CodeAnalysis: $(-not $SkipCodeAnalysis)"
    "Driver: $stagedDriver"
    "DriverSHA256: $hash"
    "CatalogSHA256: $catHash"
) -join [Environment]::NewLine
Set-Content -LiteralPath (Join-Path $release 'build-report.txt') -Value $report -Encoding UTF8

Write-Host ''
Write-Host 'WDK build and static package validation completed.'
Write-Host "Driver: $stagedDriver"
Write-Host "Driver SHA-256: $hash"
Write-Host "Catalog: $stagedCatalog"
Write-Host "Catalog SHA-256: $catHash"
