# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"expected text not found in {path}")
    text = text.replace(old, new, 1)
    p.write_text(text, encoding="utf-8")


replace_once(
    "windows/driver/extfs_driver.c",
    """/*
 * ExtFS 0.3 is a deliberately small, synchronous IFS.  It keeps every ext
 * on-disk decision in ext-core; this file translates Windows IRPs, names and
 * information records.  The first write path is intentionally narrow: it can
 * overwrite already-allocated regular-file data without changing file size,
 * block allocation, directory metadata or journal state.
 */""",
    """/*
 * ExtFS 0.9.2 is a deliberately conservative synchronous native IFS.  All ext
 * on-disk decisions remain in the portable core; this file translates Windows
 * IRPs, names, synchronization and information records.  Supported writes are
 * bounded to existing-file data overwrite plus the filesystem-specific ext2,
 * ext3 and ext4 resize paths.  Namespace mutation and paging writes remain
 * fail-closed until their later qualification checkpoints.
 */""",
)

p = Path("windows/Build-And-Validate.ps1")
text = p.read_text(encoding="utf-8")
old = r'''function Find-WindowsKitTool {
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
}'''
new = r'''function Find-WindowsKitTool {
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
if old not in text:
    raise SystemExit("expected Find-WindowsKitTool block not found")
text = text.replace(old, new, 1)
text = text.replace(
    "$infverif = Find-WindowsKitTool -Name 'InfVerif.exe'\n$inf2cat = Find-WindowsKitTool -Name 'Inf2Cat.exe'",
    "$infverif = Find-WindowsKitTool -Name 'InfVerif.exe' -RestoredPackages $packagesDir\n$inf2cat = Find-WindowsKitTool -Name 'Inf2Cat.exe' -RestoredPackages $packagesDir",
    1,
)
p.write_text(text, encoding="utf-8")
