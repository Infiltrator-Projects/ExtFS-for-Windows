<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Verification record — 0.9.2 forensic-audit hardening checkpoint

## Established Windows baseline — 11 August 2026

0.6.0 completed a native Release x64 WDK build and WDK/Visual C++ Driver Code Analysis with 0 warnings and 0 errors. InfVerif and Inf2Cat also completed with no warnings/errors, and the SYS/CAT test signatures verified.

0.7.0 and 0.8.0 were not independently WDK-tested before development continued. 0.9.1 was the GPL/SPDX maintenance checkpoint on the unqualified 0.9.0 functional code.

## 0.9.2 audit hardening

The ext2 direct-resize path enforces three storage barriers: after making the filesystem dirty, after completing data/allocation/inode mutation, and after restoring the clean superblock. Regression coverage injects failures at the first and second barriers and verifies that mutation cannot proceed before a durable dirty marker and that the clean marker is never written while mutation durability is uncertain.

0.9.2 also adds a qualification-only real-image mutator. CI builds disposable `mke2fs` ext2/ext3/ext4 images within the currently supported feature boundary, grows and shrinks an existing file through the real ExtFS metadata paths, closes/reopens the image, compares file bytes and requires a clean read-only `e2fsck` after each mutation.

The Windows smoke-test script now has an explicit `-ExerciseResize` mode for disposable test volumes. It reversibly exercises append semantics, `FileEndOfFileInformation` growth/shrink, zero-fill of newly exposed bytes and byte-for-byte restoration of the original file.

## Permanent CI gates

The 0.9.2 PR must pass both permanent workflows before release:

- Portable ExtFS CI: GCC warnings-as-errors, unit tests, real ext2/ext3/ext4 image qualification, CMake/CTest, ASan+UBSan, Clang warnings-as-errors, GCC `-fanalyzer`, Clang static analyzer, shell/XML syntax and PowerShell parse checks.
- Windows WDK CI: pinned WDK/SDK restore, Release x64 native driver build, Driver Code Analysis, InfVerif and Inf2Cat/package validation.

Final PASS results and any environment-qualified limitations are recorded here only after those workflows complete successfully. Runtime Driver Verifier and destructive Windows filesystem testing remain separate manual qualification steps on a disposable Windows VM/test volume.

## Deliberate non-claims

Persistent regular-file mtime/ctime updates remain deferred with inode metadata semantics. Paging writes, volume lock ownership, dirty-journal replay, namespace mutation, multi-leaf/deeper ext4 extent trees and 64-bit/flex_bg allocation remain outside the 0.9.2 supported mutation boundary.
