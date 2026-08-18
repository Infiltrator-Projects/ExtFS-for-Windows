# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'expected patch context not found in {path}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')

replace_once(
    'core/extfs.c',
    '''    if (new_size == inode->size) {\n        return EXTFS_OK;\n    }\n    old_blocks = (extfs_u32)extfs_div_round_up_u64(inode->size,\n                                                    volume->block_size);''',
    '''    if (new_size == inode->size) {\n        return EXTFS_OK;\n    }\n\n    /* A metadata resize cannot safely begin unless the host can provide a\n     * durability barrier. Refuse this capability gap before even the dirty\n     * superblock is written; otherwise a caller lacking flush support would\n     * be left with an avoidable persistent dirty-state mutation. */\n    if (volume->io.flush == 0) {\n        return EXTFS_ERR_UNSUPPORTED;\n    }\n\n    old_blocks = (extfs_u32)extfs_div_round_up_u64(inode->size,\n                                                    volume->block_size);'''
)

replace_once(
    'tests/test_extfs.c',
    '''        prepare_ext2_direct_resize_image(&image);\n        failures += expect(extfs_open(&volume, &io) == EXTFS_OK &&\n                           extfs_read_inode(&volume, 2U, &resized,\n                                            verify_scratch,\n                                            sizeof(verify_scratch)) == EXTFS_OK,\n                           "same-block growth ext2 image opens");''',
    '''        {\n            extfs_io no_flush = io;\n            no_flush.flush = NULL;\n            prepare_ext2_direct_resize_image(&image);\n            failures += expect(extfs_open(&volume, &no_flush) == EXTFS_OK &&\n                               extfs_read_inode(&volume, 2U, &resized,\n                                                verify_scratch,\n                                                sizeof(verify_scratch)) == EXTFS_OK,\n                               "no-flush ext2 resize image opens read-only");\n            image.write_attempts = 0U;\n            failures += expect(extfs_resize_file_ext2_direct(\n                                   &volume, &resized, 500U, resize_scratch,\n                                   sizeof(resize_scratch)) == EXTFS_ERR_UNSUPPORTED &&\n                               image.write_attempts == 0U &&\n                               (image.bytes[1024U + 0x3AU] & 1U) != 0U,\n                               "ext2 resize refuses missing durability support before any write");\n        }\n\n        prepare_ext2_direct_resize_image(&image);\n        failures += expect(extfs_open(&volume, &io) == EXTFS_OK &&\n                           extfs_read_inode(&volume, 2U, &resized,\n                                            verify_scratch,\n                                            sizeof(verify_scratch)) == EXTFS_OK,\n                           "same-block growth ext2 image opens");'''
)

print('ext2 flush preflight and regression test patched')
