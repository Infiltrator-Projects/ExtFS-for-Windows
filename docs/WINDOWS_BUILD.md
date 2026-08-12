<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Windows build

ExtFS 0.9.1 is the GPL-3.0-or-later/SPDX maintenance release of the bounded
depth-1 ext4 extent-tree checkpoint. The established 0.6.0 Windows baseline
completed both the WDK Release build and Driver Code Analysis with 0 warnings /
0 errors. Development continued through 0.7.0, 0.8.0 and 0.9.0 without independent
Windows qualification, so 0.9.1 requires a fresh WDK qualification pass before
Windows build quality can be claimed.

Use Visual Studio/WDK and NSIS, or run the supplied repository build wrapper:

```bat
BUILD-EXTFS.cmd
```

The build restores the pinned Microsoft WDK/SDK NuGet packages, compiles the
x64 kernel driver with warnings as errors, runs Driver Code Analysis, validates
the INF, generates the catalog, test-signs SYS/CAT and builds the NSIS package.

Expected setup file:

`ExtFS-for-Windows-0.9.1-experimental-x64-setup.exe`

The package is development/test signed. It is not a production-signed driver and
has not received runtime qualification in this checkpoint.

0.9.1 routes `IRP_MJ_WRITE` extension and `FileEndOfFileInformation` resize to:

- ext2: direct unjournaled allocator/resizer;
- ext3: bounded direct-file JBD2 allocator/resizer;
- ext4: checksum-aware inline or single-external-leaf JBD2 resizer, including
  first-extent creation, fragmented EOF growth, inline-to-depth1 promotion and
  depth1-to-inline collapse.

Depth > 1/multi-leaf trees, 64-bit/flex_bg allocation, create/delete/rename,
paging writes and dirty-journal replay remain refused.
