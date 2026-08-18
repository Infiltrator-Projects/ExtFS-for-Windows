# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path


def replace_if_present(path, old, new, count=None):
    p = Path(path)
    s = p.read_text(encoding='utf-8')
    if old not in s:
        print(f'already normalized or not applicable: {path}: {old!r}')
        return
    s = s.replace(old, new, -1 if count is None else count)
    p.write_text(s, encoding='utf-8')
    print(f'normalized: {path}')

replace_if_present('include/extfs/extfs.h', '#define EXTFS_VERSION_PATCH 1', '#define EXTFS_VERSION_PATCH 2', 1)
replace_if_present('include/extfs/extfs.h', 'The initial\n * 0.3 write path', 'The bounded\n * data-write path', 1)
replace_if_present('include/extfs/extfs.h', 'Reasons the conservative 0.3 in-place write path', 'Reasons the conservative bounded in-place write path', 1)
replace_if_present('include/extfs/extfs.h', '0.9.1 still\n * requires 32-byte group descriptors', '0.9.2 still\n * requires 32-byte group descriptors', 1)
replace_if_present('tools/extfs-tool.c', 'ExtFS image inspector 0.3.0', 'ExtFS image inspector 0.9.2', 1)
replace_if_present('Directory.Build.props', 'ExtFS 0.3.0 is x64-only.', 'ExtFS 0.9.2 remains x64-only; ARM64 is a 1.0 qualification target.', 1)
replace_if_present('BUILD-EXTFS.cmd', '0.9.1', '0.9.2')
replace_if_present('windows/driver/extfs.inf', '08/12/2026,0.9.1.0', '08/18/2026,0.9.2.0', 1)
replace_if_present('windows/driver/extfs.inf', 'Experimental native ext2/ext3/ext4 filesystem driver with journaled ext3 direct-file resize', 'Experimental native ext2/ext3/ext4 filesystem driver with bounded ext2/ext3/ext4 file resize', 1)
replace_if_present('windows/driver/extfs.rc', '0,9,1,0', '0,9,2,0')
replace_if_present('windows/driver/extfs.rc', '0.9.1.0', '0.9.2.0')
replace_if_present('windows/driver/extfs.rc', '0.9.1 ext4-depth1-extent-resize experimental', '0.9.2 audit-hardened ext4-depth1-extent-resize experimental', 1)
replace_if_present('windows/Build-ExperimentalSetup.ps1', '0.9.1', '0.9.2')
replace_if_present('windows/installer/Install-ExtFS.ps1', '0.9.1', '0.9.2')
replace_if_present('windows/installer/Install-ExtFS.ps1', 'Experimental native ext2/ext3/ext4 filesystem driver with journaled ext3 direct-file resize', 'Experimental native ext2/ext3/ext4 filesystem driver with bounded ext2/ext3/ext4 file resize', 1)
replace_if_present('windows/installer/Uninstall-ExtFS.ps1', '0.9.1', '0.9.2')
replace_if_present('windows/installer/extfs-installer.nsi', '0.9.1', '0.9.2')

print('0.9.2 version metadata normalization complete')
