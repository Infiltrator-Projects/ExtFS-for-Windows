# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path


def replace(path, old, new, count=None):
    p = Path(path)
    s = p.read_text(encoding='utf-8')
    if old not in s:
        raise SystemExit(f'expected text not found in {path}: {old!r}')
    s = s.replace(old, new, -1 if count is None else count)
    p.write_text(s, encoding='utf-8')

replace('include/extfs/extfs.h', '#define EXTFS_VERSION_PATCH 1', '#define EXTFS_VERSION_PATCH 2', 1)
replace('tools/extfs-tool.c', 'ExtFS image inspector 0.3.0', 'ExtFS image inspector 0.9.2', 1)
replace('Directory.Build.props', 'ExtFS 0.3.0 is x64-only.', 'ExtFS 0.9.2 remains x64-only; ARM64 is a 1.0 qualification target.', 1)
replace('BUILD-EXTFS.cmd', '0.9.1', '0.9.2')
replace('windows/driver/extfs.inf', '08/12/2026,0.9.1.0', '08/18/2026,0.9.2.0', 1)
replace('windows/driver/extfs.inf', 'Experimental native ext2/ext3/ext4 filesystem driver with journaled ext3 direct-file resize', 'Experimental native ext2/ext3/ext4 filesystem driver with bounded ext2/ext3/ext4 file resize', 1)
replace('windows/driver/extfs.rc', '0,9,1,0', '0,9,2,0')
replace('windows/driver/extfs.rc', '0.9.1.0', '0.9.2.0')
replace('windows/driver/extfs.rc', '0.9.1 ext4-depth1-extent-resize experimental', '0.9.2 audit-hardened ext4-depth1-extent-resize experimental', 1)
replace('windows/Build-ExperimentalSetup.ps1', '0.9.1', '0.9.2')
replace('windows/installer/Install-ExtFS.ps1', '0.9.1', '0.9.2')
replace('windows/installer/Install-ExtFS.ps1', 'Experimental native ext2/ext3/ext4 filesystem driver with journaled ext3 direct-file resize', 'Experimental native ext2/ext3/ext4 filesystem driver with bounded ext2/ext3/ext4 file resize', 1)
replace('windows/installer/Uninstall-ExtFS.ps1', '0.9.1', '0.9.2')
replace('windows/installer/extfs-installer.nsi', '0.9.1', '0.9.2')

print('0.9.2 version metadata normalized')
