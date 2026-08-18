<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Verification record — 0.9.1 GPL/SPDX maintenance checkpoint

## Established Windows baseline — 11 August 2026

0.6.0 completed a native Release x64 WDK build and WDK/Visual C++ Driver Code
Analysis with 0 warnings and 0 errors. InfVerif and Inf2Cat also completed with
no warnings/errors, and the SYS/CAT test signatures verified.

0.7.0 and 0.8.0 were not independently WDK-tested before development continued.
0.9.1 changes licensing/header/build metadata on top of the unqualified 0.9.0
functional checkpoint. It therefore still requires a fresh Windows WDK/Code
Analysis pass before Windows build quality can be claimed.

## 0.9.1 portable/core checks

0.9.1 intentionally changes no filesystem algorithm. The complete 0.9 unit suite
was rerun after the GPL/SPDX conversion and continues to cover the prior
inline-extent cases plus:

- promotion of a full four-extent inline root to one depth-1 index and external
  depth-0 leaf when a fifth physical run is required;
- allocation/accounting of the external extent metadata block;
- same-size read/write mapping through extents stored in the external leaf;
- external-leaf checksum generation, reopen validation and corruption refusal
  before mutation;
- shrink of the external leaf and collapse back to the inline inode root;
- release of both trailing data and the external metadata block when collapse is
  possible;
- a 2 KiB ext4 fixture proving the extent-block checksum tail is located from
  `eh_max` rather than assumed to occupy the final four bytes of the block;
- early inode checksum/state authentication before ordered-data zeroing;
- refusal of xattr-block, multi-child, depth > 1, sparse and unwritten layouts.

Executed in the source-production environment:

- GCC C11 `-Wall -Wextra -Wpedantic -Werror`: PASS
- Unit tests: PASS
- GCC ASan + UBSan: PASS
- Clang C11 warnings-as-errors: PASS
- CMake + CTest: PASS
- GCC `-fanalyzer`: PASS
- Clang static analyzer (`clang --analyze`): PASS
- SPDX inventory: PASS — every project-owned documentation/source/build file carries `GPL-3.0-or-later`; fixture payload text is intentionally excluded
- XML project/config parse: PASS
- Shell-script syntax (`bash -n`): PASS

The optional `mke2fs` integration harness was not run because `mke2fs` is not
available in the source-production environment.

0.9.1 still requires its own Windows WDK and Driver Code Analysis qualification.

## Post-0.9.1 forensic audit hardening

The ext2 direct-resize path now enforces three storage barriers: after making the
filesystem dirty, after completing data/allocation/inode mutation, and after
restoring the clean superblock. Regression coverage injects failures at the
first and second barriers and verifies that mutation cannot proceed before a
durable dirty marker and that the clean marker is never written while mutation
durability is uncertain.
