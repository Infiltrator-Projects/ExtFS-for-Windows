# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path

path = Path('windows/Build-And-Validate.ps1')
text = path.read_text(encoding='utf-8')
old = r'''function Find-WindowsKitTool {
    param([Parameter(Mandatory)][string]$Name,
          [string]$RestoredPackages)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    if ($RestoredPackages -and (Test-Path -LiteralPath $RestoredPackages)) {
        $candidate = Get-ChildItem -LiteralPath $RestoredPackages -Filter $Name -File -Recurse `
            -ErrorAction SilentlyContinue |
            Where-Object FullName -Match '\\x64\\' |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }

    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
    if (Test-Path -LiteralPath $kits) {
        $candidate = Get-ChildItem -LiteralPath $kits -Filter $Name -File -Recurse `
            -ErrorAction SilentlyContinue |
            Where-Object FullName -Match '\\x64\\' |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    throw "$Name was not found in the restored WDK/SDK packages or installed Windows Kits."
}'''
new = r'''function Find-WindowsKitTool {
    param([Parameter(Mandatory)][string]$Name,
          [string]$RestoredPackages)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    foreach ($root in @($RestoredPackages,
                         (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'))) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $candidates = @(Get-ChildItem -LiteralPath $root -Filter $Name -File -Recurse `
            -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)
        if ($candidates.Count -eq 0) { continue }

        # Prefer an x64-hosted utility when one exists. Some WDK package tools,
        # notably Inf2Cat, are distributed only as an x86-hosted executable even
        # when validating an x64 driver package; those tools are architecture-
        # neutral with respect to the package they inspect.
        $candidate = $candidates |
            Where-Object FullName -Match '\\x64\\' |
            Select-Object -First 1
        if (-not $candidate) { $candidate = $candidates | Select-Object -First 1 }
        if ($candidate) { return $candidate.FullName }
    }
    throw "$Name was not found in the restored WDK/SDK packages or installed Windows Kits."
}'''
if old not in text:
    raise SystemExit('expected Find-WindowsKitTool block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('WDK tool locator patched')
