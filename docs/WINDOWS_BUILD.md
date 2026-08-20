<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Windows build

ExtFS 0.9.3 is the Windows-lifecycle/Common-1.9 maintenance release on the bounded depth-1 ext4 extent-tree feature boundary established and audit-qualified in 0.9.2. The filesystem mutation boundary is unchanged; 0.9.3 must pass the permanent portable and Windows WDK gates from its own source before publication.

Use Visual Studio/WDK and NSIS, or run the supplied repository build wrapper:

```bat
BUILD-EXTFS.cmd
```

The build restores the pinned Microsoft WDK/SDK NuGet packages, compiles the x64 kernel driver with warnings as errors, runs Driver Code Analysis, validates the INF, generates the catalog, test-signs SYS/CAT and builds the NSIS package. The WDK validator can use tools from the restored pinned packages or an installed Windows Kit, which also permits the repository's Windows CI path to exercise the same build logic.

Expected setup file:

`ExtFS-for-Windows-0.9.3-experimental-x64-setup.exe`

The package is development/test signed. It is not a production-signed driver. See `VERIFICATION.md` for the exact current WDK/CI/runtime qualification state.

0.9.3 routes `IRP_MJ_WRITE` extension and `FileEndOfFileInformation` resize to:

- ext2: direct unjournaled allocator/resizer with explicit dirty/mutation/clean durability barriers;
- ext3: bounded direct-file JBD2 allocator/resizer;
- ext4: checksum-aware inline or single-external-leaf JBD2 resizer, including first-extent creation, fragmented EOF growth, inline-to-depth1 promotion and depth1-to-inline collapse.

`windows/test/Test-ExtFS.ps1` can perform read-only smoke qualification, reversible same-size overwrite, and an explicitly requested reversible append/extend/truncate probe against a disposable known file.

Depth > 1/multi-leaf trees, 64-bit/flex_bg allocation, create/delete/rename, paging writes, volume lock ownership and dirty-journal replay remain refused.
