<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Architecture

ExtFS keeps filesystem mechanics independent of Windows policy.

0.9.1 is a licensing-standardisation maintenance checkpoint; the architecture and
filesystem algorithms are intentionally unchanged from 0.9.0.

```text
raw volume/image
      |
host read / write / flush / wall-clock callbacks
      |
portable ext core
  - validation and traversal
  - bounded file-data writes
  - ext2 direct allocation/resize
  - JBD2 transaction engine
  - ext3 direct-file journaled resize
  - ext4 checksum-aware bounded extent-tree resize
      |
      +-- user-mode test tool
      +-- native Windows IFS
```

The core has no OS headers, heap allocator, threads or global mutable state.
Callers provide scratch buffers. On-disk sizes, offsets, counts, mappings,
checksums and arithmetic are treated as untrusted.

## Journaled metadata boundary

0.9.1 has two bounded journaled metadata-mutation families. ext3 can resize
files whose mapping fits the twelve legacy direct blocks. ext4 can resize dense
initialized extent files represented either directly in the inode or by one
external depth-0 leaf referenced by a depth-1 inode root.

For ext4 growth the core first attempts to extend the last physical run. If that
is unavailable, it can append another physical run. A full four-entry inline
root is promoted to an allocated external leaf when a fifth extent is required.
The single external leaf can then hold additional extents up to the bounded
implementation limit and the on-disk leaf capacity. Shrink removes/trims trailing
extents and collapses the leaf back into the inline root when possible. One
resize may change allocation metadata in only one block group.

When allocation changes, the core assembles complete home-block images for the
block bitmap, group-descriptor block, inode-table block, primary-superblock block
and, when present, the external extent leaf. ext4 validates/rebuilds
`metadata_csum` values before those images enter the JBD2 transaction. Newly
visible data is zeroed and flushed before a growth transaction can advertise it
through inode metadata.

Depth > 1 trees, multiple leaf children, 64-bit group descriptors, multi-group
allocation, namespace changes and dirty-journal replay remain disconnected and
fail closed.

## Windows layer

The Windows component is a native filesystem driver, not a minifilter. Windows
IRP handlers translate I/O requests and synchronization into portable-core
operations. File-data serialization remains per shared FCB; allocation/resize
also takes the per-volume metadata resource. If a journal failure leaves the
volume recovery-required, the Windows layer disables further writes.
