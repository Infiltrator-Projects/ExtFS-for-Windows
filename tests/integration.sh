#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir="$project_dir/build/integration"
fixture_dir="$project_dir/tests/fixtures"
tool="$project_dir/build/extfs-tool"
stage_dir="$test_dir/stage"

# Build a fixture that exercises ordinary files, nested paths, symlinks,
# sparse mappings and enough directory entries to force ext4 HTree indexing.
mkdir -p "$test_dir"
rm -rf "$stage_dir"
mkdir -p "$stage_dir"
cp -R "$fixture_dir/." "$stage_dir/"
dd if=/dev/urandom of="$stage_dir/big.bin" bs=1048576 count=2 status=none
dd if=/dev/urandom of="$test_dir/sparse-seed.bin" bs=1024 count=1 status=none
truncate -s 8M "$stage_dir/sparse.bin"
sparse_extent=0
while [ "$sparse_extent" -lt 12 ]; do
    dd if="$test_dir/sparse-seed.bin" of="$stage_dir/sparse.bin" bs=1 \
        seek=$((sparse_extent * 524288)) conv=notrunc status=none
    sparse_extent=$((sparse_extent + 1))
done
ln -s hello.txt "$stage_dir/link-to-hello"

entry=0
while [ "$entry" -lt 300 ]; do
    cp "$fixture_dir/hello.txt" "$stage_dir/subdir/item-$entry.txt"
    entry=$((entry + 1))
done

# Recreate the same logical fixture as ext2, ext3 and ext4, then verify that
# lookup and extraction reproduce the host-side bytes exactly.
for filesystem in ext2 ext3 ext4; do
    image="$test_dir/$filesystem.img"
    extracted="$test_dir/$filesystem-hello.txt"
    truncate -s 96M "$image"
    mke2fs -q -F -t "$filesystem" -b 1024 -L "EXTFS-$filesystem" \
        -d "$stage_dir" "$image"
    e2fsck -f -y -D "$image" > "$test_dir/$filesystem-e2fsck.txt" 2>&1
    "$tool" info "$image" > "$test_dir/$filesystem-info.txt"
    "$tool" ls "$image" / > "$test_dir/$filesystem-root.txt"
    "$tool" extract "$image" /hello.txt "$extracted"
    cmp "$stage_dir/hello.txt" "$extracted"
    "$tool" cat "$image" /subdir/nested.txt > "$test_dir/$filesystem-nested.txt"
    cmp "$stage_dir/subdir/nested.txt" "$test_dir/$filesystem-nested.txt"
    "$tool" extract "$image" /big.bin "$test_dir/$filesystem-big.bin"
    cmp "$stage_dir/big.bin" "$test_dir/$filesystem-big.bin"
    "$tool" extract "$image" /sparse.bin "$test_dir/$filesystem-sparse.bin"
    cmp "$stage_dir/sparse.bin" "$test_dir/$filesystem-sparse.bin"
    test "$("$tool" cat "$image" /link-to-hello)" = "hello.txt"
    "$tool" ls "$image" /subdir > "$test_dir/$filesystem-subdir.txt"
    grep 'item-299.txt' "$test_dir/$filesystem-subdir.txt" > /dev/null
done

# Flip one byte covered by the ext4 superblock checksum.  Acceptance here
# would mean metadata_csum validation regressed.
corrupt_image="$test_dir/ext4-corrupt-superblock.img"
cp "$test_dir/ext4.img" "$corrupt_image"
printf 'Z' | dd of="$corrupt_image" bs=1 seek=1144 conv=notrunc status=none
if "$tool" info "$corrupt_image" > "$test_dir/corrupt-output.txt" 2>&1; then
    echo "Corrupted ext4 superblock was incorrectly accepted." >&2
    exit 1
fi
grep 'metadata checksum mismatch' "$test_dir/corrupt-output.txt" > /dev/null

echo "Ext2, ext3 and ext4 integration tests passed."
