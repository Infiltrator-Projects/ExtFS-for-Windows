<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# ExtFS for Windows

ExtFS is an original native Windows filesystem project written in C. The goal is
native ext2/ext3/ext4 access through the normal Windows I/O system. A later
research goal is an ext4 system volume capable of carrying Windows.

Version 0.9.1 is a licensing-standardisation maintenance checkpoint. It changes
the project licence from MIT to GPL-3.0-or-later and adds SPDX identifiers across
the source, build configuration and documentation without intentionally changing
filesystem behaviour. The bounded external ext4 extent-tree mutation path from
0.9 remains the current functional checkpoint. Eligible clean ext4 regular files
may use either the inode-resident depth-0 root or one external depth-0 leaf
referenced by a depth-1 inode root. A full
four-entry inline root can be promoted to that leaf when growth needs another
extent; later growth may merge or append initialized extents in the same leaf,
and shrink can collapse the tree back into the inode when four or fewer extents
remain. The external leaf checksum is validated and rebuilt at its `eh_max` tail
offset and the metadata extent block is included in allocation and `i_blocks`
accounting.

Earlier capabilities remain: read access to supported ext2/ext3/ext4, same-size
overwrite of allocated initialized regular-file data, ext2 direct-file resize,
journaled ext3 direct-file resize, and checksum-aware inline ext4 resize.
Depth greater than one, more than one external leaf, 64-bit group descriptors,
multi-group allocation in one resize, sparse/unwritten allocation, namespace
mutation and dirty-journal replay remain disabled. Unsupported or unsafe layouts
fail closed.

The portable core is freestanding C: no operating-system headers, internal heap
allocation, threads or global mutable state.

## Portable build

```sh
make
./build/test-extfs
```

`build/extfs-tool` is a read-only image inspector.

## Windows build

On Windows with Visual Studio/WDK and NSIS:

```bat
BUILD-EXTFS.cmd
```

The expected package is
`ExtFS-for-Windows-0.9.1-experimental-x64-setup.exe`. It is a test-signed
experimental kernel driver, not a production filesystem.

## Deliberate boundaries

Create/delete/rename/mkdir, dirty-journal replay, depth > 1 or multi-leaf ext4
extent-tree mutation, 64-bit/flex_bg metadata allocation, classic indirect-block
allocation, paging writes, external journals, `meta_bg`, `bigalloc`, inline data,
encrypted/casefolded layouts, MMP writes and unknown write-sensitive features
remain refused.

See `docs/FEATURE_SUPPORT.md`, `ROADMAP.md` and `VERIFICATION.md` for the exact
checkpoint status.


## License

ExtFS for Windows is licensed under the GNU General Public License, version 3 or
(at your option) any later version: `GPL-3.0-or-later`. See `LICENSE`.
