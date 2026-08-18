<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Security and safety boundary

ExtFS remains an experimental kernel filesystem driver. A defect can crash
Windows or corrupt a test filesystem. Use only backed-up/disposable media and a
disposable test machine/VM until runtime qualification is complete.

0.9.1 is a licensing-only maintenance checkpoint and intentionally keeps the
0.9.0 fail-closed filesystem behaviour, including the bounded external ext4
extent leaf. The post-0.9.1 audit hardening adds explicit ext2 durability
barriers: the dirty superblock is flushed before mutation, all mutation is
flushed before the clean marker, and the clean marker is flushed before success
is reported. It still requires 32-byte group descriptors, `metadata_csum`,
a supported clean internal JBD2 journal, and at most one allocation group change
per resize. Bitmap/group/inode/superblock and external extent-leaf checksums are
validated or rebuilt before journal commit. Newly allocated data is zeroed and
flushed before growth metadata becomes durable.

Depth greater than one, more than one external leaf, sparse or unwritten
allocation, 64-bit/flex_bg layouts, dirty journals, external inode xattr blocks
and unknown write-sensitive features remain refused by the bounded resizer.
