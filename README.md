<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# ExtFS for Windows

ExtFS is an original native Windows filesystem project written primarily in C. The goal is native ext2/ext3/ext4 access through the normal Windows I/O system. A later research goal is an ext4 system volume capable of carrying Windows.

Version 0.9.3 is a maintenance release on the 0.9.2 audit-hardened feature boundary. It supplies the Windows-required advanced FCB header, makes mapped-section closure authoritative before FCB reclamation or removable-media refresh, resynchronises write/read-only device characteristics, pins the staged driver version at 0.9.3.0, and uses Infiltratr Common 1.9.0 as the kernel-safe shared compiler-annotation dependency. It does not expand the supported ext filesystem mutation boundary.

The current bounded ext4 mutation path supports eligible clean regular files represented either by the inode-resident depth-0 extent root or by one external depth-0 leaf referenced by a depth-1 inode root. A full four-entry inline root can be promoted to that leaf when growth needs another extent; later growth may merge or append initialized extents in the same leaf, and shrink can collapse the tree back into the inode when four or fewer extents remain. External-leaf checksums, allocation accounting and inode/group/superblock checksums are validated or rebuilt before commit.

Earlier capabilities remain: read access to supported ext2/ext3/ext4, same-size overwrite of allocated initialized regular-file data, ext2 direct-file resize, journaled ext3 direct-file resize, and checksum-aware bounded ext4 resize. Depth greater than one, more than one external leaf, 64-bit/flex_bg allocation, multi-group allocation in one resize, sparse/unwritten allocation, namespace mutation and dirty-journal replay remain disabled. Unsupported or unsafe layouts fail closed.

The portable core is freestanding C: no operating-system headers, internal heap allocation, threads or global mutable state. The Windows adapter consumes only the kernel-safe compiler-annotation header from Infiltratr Common 1.9.0, pinned as a Git submodule; Common user-mode runtime sources are not linked into `extfs.sys`.

## Portable build

```sh
make
./build/test-extfs
make integration
```

`build/extfs-tool` is a read-only image inspector. `build/extfs-mutate-test` is a qualification-only helper used against disposable images by the integration suite.

## Windows build

On Windows with Visual Studio/WDK and NSIS, clone with submodules so the exact Infiltratr Common dependency is present:

```bat
git clone --recurse-submodules https://github.com/The-First-Infiltrator/ExtFS-for-Windows.git
cd ExtFS-for-Windows
BUILD-EXTFS.cmd setup x64
BUILD-EXTFS.cmd setup ARM64
```

The expected packages are `ExtFS-for-Windows-0.9.3-experimental-x64-setup.exe` and `ExtFS-for-Windows-0.9.3-experimental-arm64-setup.exe`. Both are test-signed experimental kernel drivers, not production filesystems. The installer and build pipeline verify the driver PE architecture before packaging or installation. See `docs/ARM64_TESTING.md` before replacing any existing ARM64 filesystem driver.

## Deliberate boundaries

Create/delete/rename/mkdir, dirty-journal replay, depth > 1 or multi-leaf ext4 extent-tree mutation, 64-bit/flex_bg metadata allocation, classic indirect-block allocation, paging writes, external journals, `meta_bg`, `bigalloc`, inline data, encrypted/casefolded layouts, MMP writes and unknown write-sensitive features remain refused.

See `docs/FEATURE_SUPPORT.md`, `ROADMAP.md` and `VERIFICATION.md` for the exact checkpoint status.

## License

ExtFS for Windows is licensed under the GNU General Public License, version 3 or (at your option) any later version: `GPL-3.0-or-later`. See `LICENSE`.
