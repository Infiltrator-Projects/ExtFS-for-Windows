<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# ExtFS for Windows

ExtFS is an original native Windows filesystem project written primarily in C. The goal is native ext2/ext3/ext4 access through the normal Windows I/O system. A later research goal is an ext4 system volume capable of carrying Windows.

Version 0.9.5 is an installer-only architecture-detection hotfix carrying the already-qualified 0.9.3.0 filesystem driver. It removes the broken machine-scoped `PROCESSOR_ARCHITECTURE` lookup that could falsely reject genuine x64 Windows systems, uses `RuntimeInformation.OSArchitecture` with a WOW64-safe fallback, retains independent PE machine validation, and includes the 0.9.4 filesystem-service ImagePath fix and service-contract checks. The underlying filesystem feature boundary is unchanged from 0.9.3 and continues to use Infiltratr Common 1.9.0 as the kernel-safe shared compiler-annotation dependency.

**Secure Boot is a production requirement.** The finished public ExtFS driver is intended to install and load on stock supported Windows systems with UEFI Secure Boot left enabled. The existing self-signed 0.9.x installer is therefore development-only. Production releases must consume a Microsoft Hardware Dev Center production-signed driver package; users must not be expected to disable Secure Boot or enable TESTSIGNING. `windows/Build-HardwareSubmission.ps1` creates the CAB submission bundle and `docs/SECURE_BOOT_SIGNING.md` documents the signing/release path.

The current bounded ext4 mutation path supports eligible clean regular files represented either by the inode-resident depth-0 extent root or by one external depth-0 leaf referenced by a depth-1 inode root. A full four-entry inline root can be promoted to that leaf when growth needs another extent; later growth may merge or append initialized extents in the same leaf, and shrink can collapse the tree back into the inode when four or fewer extents remain. External-leaf checksums, allocation accounting and inode/group/superblock checksums are validated or rebuilt before commit.

Earlier capabilities remain: read access to supported ext2/ext3/ext4, same-size overwrite of allocated initialized regular-file data, ext2 direct-file resize, journaled ext3 direct-file resize, bounded ext2/ext3 classic single-indirect resize, and checksum-aware bounded ext4 resize. Double/triple-indirect classic mutation and broader unsupported indirect layouts remain fail-closed.

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

The expected development packages are `ExtFS-for-Windows-0.9.5-experimental-x64-setup.exe` and `ExtFS-for-Windows-0.9.5-experimental-arm64-setup.exe`. Both are test-signed experimental kernel-driver packages and are not the production distribution path. For a Secure-Boot-capable submission bundle, run:

```powershell
.\windows\Build-HardwareSubmission.ps1 -Platform x64
```

See `docs/SECURE_BOOT_SIGNING.md` for Hardware Dev Center/WHCP production signing and `docs/ARM64_TESTING.md` for ARM64 qualification.

## Deliberate boundaries

Create/delete/rename/mkdir, dirty-journal replay, ext2/ext3 double/triple-indirect mutation, depth > 1 or multi-leaf ext4 extent-tree mutation, 64-bit/flex_bg metadata allocation, multi-group allocation in one resize, sparse/unwritten allocation, paging writes, external journals, `meta_bg`, `bigalloc`, inline data, encrypted/casefolded layouts, MMP writes and unknown write-sensitive features remain refused.

See `docs/FEATURE_SUPPORT.md`, `ROADMAP.md` and `VERIFICATION.md` for the exact checkpoint status.

## License

ExtFS for Windows is licensed under the GNU General Public License, version 3 or (at your option) any later version: `GPL-3.0-or-later`. See `LICENSE`.