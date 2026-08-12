<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Feature support in 0.9.1

0.9.1 changes licensing/SPDX metadata only; capability boundaries are unchanged from 0.9.0.

| Capability | Status | Boundary |
|---|---|---|
| ext2 read/traverse | Supported | Validated supported layouts |
| ext3 read/traverse | Supported | Clean supported layouts |
| ext4 read/traverse | Supported subset | Unsupported modern layouts fail closed |
| Same-size regular-file overwrite | Supported subset | Existing allocated initialized blocks only |
| ext2 direct-file growth/truncate | Experimental | First 12 direct blocks only |
| ext3 direct-file growth/truncate | Experimental | Clean internal JBD2; legacy direct layout; one allocation/free group per resize |
| ext4 inline-root growth/truncate | Experimental | Zero to four initialized depth-0 extents in `inode.i_block` |
| ext4 depth-1 extent-tree growth/truncate | Experimental | Exactly one external depth-0 leaf and one root index; dense initialized extents only |
| ext4 inline-to-external promotion | Experimental | Full four-entry inline root can move to one newly allocated external leaf |
| ext4 external-to-inline collapse | Experimental | Shrink collapses to inode root when four or fewer extents remain |
| ext4 metadata checksums | Mutation support | Bitmap, group descriptor, inode, primary superblock and external extent leaf rebuilt/verified |
| ext4 extent-block checksum tail | Supported | Tail located from `eh_max`; not assumed to be final four bytes of block |
| Multiple external leaves / depth > 1 | Refused | Split/merge/index propagation not implemented yet |
| 64-bit/flex_bg ext4 allocation | Refused | 64-byte descriptors and broader placement/accounting not implemented |
| Multi-group allocation per resize | Refused | One bitmap/descriptor pair per resize transaction |
| Sparse/unwritten allocation | Refused | No hole allocation or unwritten conversion yet |
| External inode xattr block during resize | Refused | Bounded `i_blocks` accounting does not yet include it |
| Create/delete/rename/mkdir/rmdir | Refused | Namespace mutation not implemented |
| Dirty-journal replay | Refused | Recovery engine not implemented |
| External JBD2 journal | Refused | Internal journal only |
| JBD2 checksum v2/v3 | Transaction writer supports | CRC32C only |
| JBD2 async/fast commit/checksum v1 | Refused | Not implemented |
| Paging writes | Refused | Cached/paging writer not qualified |
| `meta_bg`, `bigalloc`, inline data, encrypted/casefold | Refused for mutation | Layout not implemented |
| MMP | Refused for writes | Multi-mount protection not implemented |
