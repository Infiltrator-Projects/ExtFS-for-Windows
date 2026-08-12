# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z]:?$')]
    [string]$DriveLetter,
    [string]$KnownFile,
    [switch]$ExerciseInPlaceWrite
)

$ErrorActionPreference = 'Stop'
$drive = $DriveLetter.TrimEnd(':').ToUpperInvariant()
$root = "$drive`:\"
if (-not (Test-Path -LiteralPath $root)) { throw "Drive $root is not mounted." }

$results = [ordered]@{
    Date = [DateTime]::Now.ToString('o')
    Drive = $root
    RootEnumeration = $false
    ReadFile = $null
    ReadBytes = 0
    CopyOut = $false
    InPlaceWrite = $null
    InPlaceWriteRestored = $null
    WriteFileRefused = $false
    CreateDirectoryRefused = $false
    StillReadableAfterWriteProbes = $false
}

Write-Host "Enumerating $root ..."
$entries = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)
$results.RootEnumeration = $true
Write-Host "Root entries: $($entries.Count)"

$file = $null
if ($KnownFile) {
    $candidate = if ([IO.Path]::IsPathRooted($KnownFile)) {
        $KnownFile
    } else {
        Join-Path $root $KnownFile
    }
    $file = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
    if ($file.PSIsContainer) { throw "$candidate is a directory, not a file." }
} else {
    $file = $entries | Where-Object { -not $_.PSIsContainer } | Select-Object -First 1
}

if ($file) {
    $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $buffer = New-Object byte[] 65536
        $count = $stream.Read($buffer, 0, $buffer.Length)
        $results.ReadFile = $file.FullName
        $results.ReadBytes = $count
    } finally {
        $stream.Dispose()
    }

    $copyDir = Join-Path $env:TEMP 'ExtFS-Qualification'
    New-Item -ItemType Directory -Path $copyDir -Force | Out-Null
    $copyPath = Join-Path $copyDir $file.Name
    Copy-Item -LiteralPath $file.FullName -Destination $copyPath -Force -ErrorAction Stop
    if ((Get-Item -LiteralPath $copyPath).Length -ne $file.Length) {
        throw 'The copied file length does not match the source length.'
    }
    $results.CopyOut = $true

    if ($ExerciseInPlaceWrite) {
        if ($file.Length -lt 8) { throw 'Known file must be at least 8 bytes for the in-place write test.' }
        $rw = [IO.File]::Open($file.FullName, [IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
        try {
            $original = New-Object byte[] 8
            if ($rw.Read($original, 0, 8) -ne 8) { throw 'Could not read write-test prefix.' }
            $marker = [Text.Encoding]::ASCII.GetBytes('EXTFS060')
            $rw.Position = 0
            $rw.Write($marker, 0, $marker.Length)
            $rw.Flush()
            $rw.Position = 0
            $check = New-Object byte[] 8
            if ($rw.Read($check, 0, 8) -ne 8 -or
                [Convert]::ToBase64String($marker) -ne [Convert]::ToBase64String($check)) {
                throw 'In-place write verification failed.'
            }
            $results.InPlaceWrite = $true
            $rw.Position = 0
            $rw.Write($original, 0, $original.Length)
            $rw.Flush()
            $rw.Position = 0
            $restored = New-Object byte[] 8
            if ($rw.Read($restored, 0, 8) -ne 8 -or
                [Convert]::ToBase64String($original) -ne [Convert]::ToBase64String($restored)) {
                throw 'Original bytes were not restored after the write test.'
            }
            $results.InPlaceWriteRestored = $true
        } finally {
            $rw.Dispose()
        }
    }
}

if ($ExerciseInPlaceWrite -and -not $file) {
    throw '-ExerciseInPlaceWrite requires -KnownFile or a root-level regular file.'
}

$probeFile = Join-Path $root '__extfs_write_probe.tmp'
try {
    [IO.File]::WriteAllText($probeFile, 'ExtFS write probe')
    Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
    throw 'WRITE-SAFETY FAILURE: creating a file on the ExtFS volume unexpectedly succeeded.'
} catch {
    if ($_.Exception.Message -like 'WRITE-SAFETY FAILURE:*') { throw }
    $results.WriteFileRefused = $true
}

$probeDirectory = Join-Path $root '__extfs_directory_probe'
try {
    [IO.Directory]::CreateDirectory($probeDirectory) | Out-Null
    Remove-Item -LiteralPath $probeDirectory -Force -Recurse -ErrorAction SilentlyContinue
    throw 'WRITE-SAFETY FAILURE: creating a directory on the ExtFS volume unexpectedly succeeded.'
} catch {
    if ($_.Exception.Message -like 'WRITE-SAFETY FAILURE:*') { throw }
    $results.CreateDirectoryRefused = $true
}

@(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop) | Out-Null
$results.StillReadableAfterWriteProbes = $true

$report = Join-Path $env:TEMP "ExtFS-qualification-$drive-$([DateTime]::Now.ToString('yyyyMMdd-HHmmss')).json"
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host ''
Write-Host 'ExtFS 0.9.1 smoke test passed.'
Write-Host "Report: $report"
$results | Format-List | Out-Host
