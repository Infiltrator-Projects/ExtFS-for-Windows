# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import re


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:80]!r}")
    p.write_text(text.replace(old, new, 1))


replace_once("include/extfs/extfs.h",
             "#define EXTFS_VERSION_PATCH 2",
             "#define EXTFS_VERSION_PATCH 3")

p = Path("core/extfs.c")
text = p.read_text()
m = re.search(r"(const char \*extfs_status_string\(extfs_status status\)\s*\{[\s\S]*?)(\n\})", text)
if not m:
    raise SystemExit("extfs_status_string not found")
body = m.group(1)
if "EXTFS_ERR_NO_SPACE" not in body:
    default = re.search(r"(?m)^\s*default:\s+return \"unknown error\";", body)
    if not default:
        raise SystemExit("extfs_status_string default not found")
    insertion = '        case EXTFS_ERR_NO_SPACE:        return "no space left on device";\n'
    body = body[:default.start()] + insertion + body[default.start():]
    text = text[:m.start(1)] + body + text[m.end(1):]
    p.write_text(text)

replace_once("windows/driver/extfs_driver.h",
             "    volatile LONG FileObjectCount;\n    BOOLEAN Dismounted;",
             "    volatile LONG FileObjectCount;\n    PFILE_OBJECT VolumeLockFileObject;\n    BOOLEAN Dismounted;")

replace_once("windows/driver/extfs_driver.c",
             "    BOOLEAN CaseSensitive;\n    BOOLEAN Found;\n} EXTFS_DIRENT_PICK, *PEXTFS_DIRENT_PICK;",
             "    BOOLEAN CaseSensitive;\n    BOOLEAN Found;\n    NTSTATUS NameStatus;\n} EXTFS_DIRENT_PICK, *PEXTFS_DIRENT_PICK;")

replace_once("windows/driver/extfs_driver.c",
'''    status = ExtfsUtf8ToUnicode(Name, NameLength, unicode,
                                EXTFS_MAX_NAME_LENGTH, &unicodeLength);
    if (!NT_SUCCESS(status) ||
        !ExtfsWildcardMatch(pick->Pattern, pick->PatternLength,
                            unicode, unicodeLength, pick->CaseSensitive)) {
        return 0;
    }''',
'''    status = ExtfsUtf8ToUnicode(Name, NameLength, unicode,
                                EXTFS_MAX_NAME_LENGTH, &unicodeLength);
    if (!NT_SUCCESS(status)) {
        /* ext directory names are raw bytes. Never make a live entry silently
         * disappear merely because Windows cannot represent it as UTF-16. */
        pick->NameStatus = status;
        return 1;
    }
    if (!ExtfsWildcardMatch(pick->Pattern, pick->PatternLength,
                            unicode, unicodeLength, pick->CaseSensitive)) {
        return 0;
    }''')

replace_once("windows/driver/extfs_driver.c",
'''    if (status != EXTFS_OK && status != EXTFS_STOP)
        return ExtfsStatusToNt(status);
    return Pick->Found ? STATUS_SUCCESS : STATUS_NO_MORE_FILES;''',
'''    if (status != EXTFS_OK && status != EXTFS_STOP)
        return ExtfsStatusToNt(status);
    if (!NT_SUCCESS(Pick->NameStatus)) return Pick->NameStatus;
    return Pick->Found ? STATUS_SUCCESS : STATUS_NO_MORE_FILES;''')

replace_once("windows/driver/extfs_driver.c",
'''    IoRemoveShareAccess(FileObject, &fcb->ShareAccess);
    if (fcb->HandleCount > 0) --fcb->HandleCount;
    ccb->CleanupComplete = TRUE;''',
'''    IoRemoveShareAccess(FileObject, &fcb->ShareAccess);
    if (fcb->HandleCount > 0) --fcb->HandleCount;
    if (fcb->VolumeOpen && fcb->Vcb->VolumeLockFileObject == FileObject) {
        KIRQL savedIrql;
        IoAcquireVpbSpinLock(&savedIrql);
        fcb->Vcb->Vpb->Flags &= (USHORT)~VPB_LOCKED;
        IoReleaseVpbSpinLock(savedIrql);
        fcb->Vcb->VolumeLockFileObject = NULL;
    }
    ccb->CleanupComplete = TRUE;''')

p = Path("windows/driver/extfs_driver.c")
text = p.read_text()
anchor = "NTSTATUS ExtfsDispatchFileSystemControl(PDEVICE_OBJECT DeviceObject, PIRP Irp)\n{"
if text.count(anchor) != 1:
    raise SystemExit("FSCTL dispatcher anchor mismatch")
helpers = r'''static NTSTATUS ExtfsLockMountedVolume(PEXTFS_VCB Vcb, PFILE_OBJECT FileObject)
{
    PEXTFS_FCB ownerFcb = ExtfsFcbFromFile(FileObject);
    LIST_ENTRY reapList;
    PLIST_ENTRY entry;
    NTSTATUS status = STATUS_ACCESS_DENIED;
    KIRQL savedIrql;

    if (ownerFcb == NULL || ownerFcb->Vcb != Vcb || !ownerFcb->VolumeOpen)
        return STATUS_INVALID_PARAMETER;

    InitializeListHead(&reapList);
    ExtfsAcquireFcbList(Vcb);
    ExtfsCollectReapableFcbsLocked(Vcb, &reapList, FALSE);
    if (Vcb->Dismounted) {
        status = STATUS_VOLUME_DISMOUNTED;
        goto ExitLocked;
    }
    if (Vcb->VolumeLockFileObject != NULL ||
        Vcb->OpenHandleCount != 1 || Vcb->FileObjectCount != 1)
        goto ExitLocked;

    for (entry = Vcb->FcbList.Flink; entry != &Vcb->FcbList; entry = entry->Flink) {
        PEXTFS_FCB fcb = CONTAINING_RECORD(entry, EXTFS_FCB, Links);
        if (fcb != ownerFcb) goto ExitLocked;
    }

    IoAcquireVpbSpinLock(&savedIrql);
    if ((Vcb->Vpb->Flags & VPB_LOCKED) == 0U) {
        Vcb->Vpb->Flags |= VPB_LOCKED;
        Vcb->VolumeLockFileObject = FileObject;
        status = STATUS_SUCCESS;
    }
    IoReleaseVpbSpinLock(savedIrql);

ExitLocked:
    ExtfsReleaseFcbList(Vcb);
    ExtfsDestroyFcbList(&reapList);

    if (NT_SUCCESS(status) && Vcb->WriteEnabled) {
        NTSTATUS flushStatus = ExtfsFlushLowerDevice(&Vcb->Reader);
        if (!NT_SUCCESS(flushStatus)) {
            ExtfsAcquireFcbList(Vcb);
            if (Vcb->VolumeLockFileObject == FileObject) {
                IoAcquireVpbSpinLock(&savedIrql);
                Vcb->Vpb->Flags &= (USHORT)~VPB_LOCKED;
                IoReleaseVpbSpinLock(savedIrql);
                Vcb->VolumeLockFileObject = NULL;
            }
            ExtfsReleaseFcbList(Vcb);
            status = flushStatus;
        }
    }
    return status;
}

static NTSTATUS ExtfsUnlockMountedVolume(PEXTFS_VCB Vcb, PFILE_OBJECT FileObject)
{
    PEXTFS_FCB ownerFcb = ExtfsFcbFromFile(FileObject);
    NTSTATUS status = STATUS_NOT_LOCKED;
    KIRQL savedIrql;

    if (ownerFcb == NULL || ownerFcb->Vcb != Vcb || !ownerFcb->VolumeOpen)
        return STATUS_INVALID_PARAMETER;

    ExtfsAcquireFcbList(Vcb);
    if (Vcb->VolumeLockFileObject == FileObject) {
        IoAcquireVpbSpinLock(&savedIrql);
        Vcb->Vpb->Flags &= (USHORT)~VPB_LOCKED;
        IoReleaseVpbSpinLock(savedIrql);
        Vcb->VolumeLockFileObject = NULL;
        status = STATUS_SUCCESS;
    }
    ExtfsReleaseFcbList(Vcb);
    return status;
}

static NTSTATUS ExtfsDismountLockedVolume(PEXTFS_VCB Vcb, PFILE_OBJECT FileObject)
{
    PEXTFS_FCB ownerFcb = ExtfsFcbFromFile(FileObject);
    NTSTATUS status;
    KIRQL savedIrql;

    if (ownerFcb == NULL || ownerFcb->Vcb != Vcb || !ownerFcb->VolumeOpen)
        return STATUS_INVALID_PARAMETER;

    ExtfsAcquireFcbList(Vcb);
    if (Vcb->VolumeLockFileObject != FileObject) {
        ExtfsReleaseFcbList(Vcb);
        return STATUS_ACCESS_DENIED;
    }
    if (Vcb->Dismounted) {
        ExtfsReleaseFcbList(Vcb);
        return STATUS_VOLUME_DISMOUNTED;
    }
    ExtfsReleaseFcbList(Vcb);

    status = Vcb->WriteEnabled ? ExtfsFlushLowerDevice(&Vcb->Reader) : STATUS_SUCCESS;
    if (!NT_SUCCESS(status)) return status;

    ExtfsAcquireFcbList(Vcb);
    if (Vcb->VolumeLockFileObject != FileObject) {
        ExtfsReleaseFcbList(Vcb);
        return STATUS_ACCESS_DENIED;
    }
    Vcb->Dismounted = TRUE;
    IoAcquireVpbSpinLock(&savedIrql);
    Vcb->Vpb->Flags &= (USHORT)~VPB_MOUNTED;
    IoReleaseVpbSpinLock(savedIrql);
    ExtfsReleaseFcbList(Vcb);
    return STATUS_SUCCESS;
}

'''
p.write_text(text.replace(anchor, helpers + anchor, 1))

replace_once("windows/driver/extfs_driver.c",
'''        case FSCTL_LOCK_VOLUME:
        case FSCTL_UNLOCK_VOLUME:
            /* Exclusive lock ownership is not implemented yet; refusing the
             * operation is safer than setting VPB_LOCKED without enforcement. */
            status = STATUS_NOT_SUPPORTED;
            break;''',
'''        case FSCTL_LOCK_VOLUME:
            status = ExtfsLockMountedVolume(vcb, stack->FileObject);
            break;
        case FSCTL_UNLOCK_VOLUME:
            status = ExtfsUnlockMountedVolume(vcb, stack->FileObject);
            break;
        case FSCTL_DISMOUNT_VOLUME:
            status = ExtfsDismountLockedVolume(vcb, stack->FileObject);
            break;''')

# Existing file objects cannot continue normal filesystem I/O after a locked dismount.
p = Path("windows/driver/extfs_driver.c")
text = p.read_text()
old = '''    if (fcb == NULL || fcb->VolumeOpen) {
        return ExtfsCompleteIrp(Irp, STATUS_INVALID_DEVICE_REQUEST, 0U);
    }
    if (extfs_inode_type(&fcb->Inode) == EXTFS_NODE_DIRECTORY) {'''
if old not in text:
    raise SystemExit("read guard anchor missing")
text = text.replace(old, '''    if (fcb == NULL || fcb->VolumeOpen) {
        return ExtfsCompleteIrp(Irp, STATUS_INVALID_DEVICE_REQUEST, 0U);
    }
    if (fcb->Vcb->Dismounted)
        return ExtfsCompleteIrp(Irp, STATUS_VOLUME_DISMOUNTED, 0U);
    if (extfs_inode_type(&fcb->Inode) == EXTFS_NODE_DIRECTORY) {''', 1)
old = '''    if (fcb == NULL || ccb == NULL || fcb->VolumeOpen)
        return ExtfsCompleteIrp(Irp, STATUS_INVALID_DEVICE_REQUEST, 0U);
    if (!fcb->Vcb->WriteEnabled)'''
if text.count(old) < 2:
    raise SystemExit("write/set-information guard anchors missing")
new = '''    if (fcb == NULL || ccb == NULL || fcb->VolumeOpen)
        return ExtfsCompleteIrp(Irp, STATUS_INVALID_DEVICE_REQUEST, 0U);
    if (fcb->Vcb->Dismounted)
        return ExtfsCompleteIrp(Irp, STATUS_VOLUME_DISMOUNTED, 0U);
    if (!fcb->Vcb->WriteEnabled)'''
text = text.replace(old, new, 2)
old = '''    if (fcb == NULL || ccb == NULL || buffer == NULL) {
        return ExtfsCompleteIrp(Irp, STATUS_INVALID_PARAMETER, 0U);
    }
    ExtfsZeroMemory(buffer, length);'''
if text.count(old) != 1:
    raise SystemExit("query-information guard anchor missing")
text = text.replace(old, '''    if (fcb == NULL || ccb == NULL || buffer == NULL) {
        return ExtfsCompleteIrp(Irp, STATUS_INVALID_PARAMETER, 0U);
    }
    if (fcb->Vcb->Dismounted)
        return ExtfsCompleteIrp(Irp, STATUS_VOLUME_DISMOUNTED, 0U);
    ExtfsZeroMemory(buffer, length);''', 1)
old = '''    if (fcb == NULL || ccb == NULL ||
        extfs_inode_type(&fcb->Inode) != EXTFS_NODE_DIRECTORY ||'''
if text.count(old) != 1:
    raise SystemExit("directory-control guard anchor missing")
text = text.replace(old, '''    if (fcb != NULL && fcb->Vcb->Dismounted)
        return ExtfsCompleteIrp(Irp, STATUS_VOLUME_DISMOUNTED, 0U);
    if (fcb == NULL || ccb == NULL ||
        extfs_inode_type(&fcb->Inode) != EXTFS_NODE_DIRECTORY ||''', 1)
p.write_text(text)

Path("windows/test/Test-FilesystemContracts.ps1").write_text(r'''# SPDX-License-Identifier: GPL-3.0-or-later
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$driver = Get-Content -LiteralPath (Join-Path $root 'windows\driver\extfs_driver.c') -Raw
$header = Get-Content -LiteralPath (Join-Path $root 'windows\driver\extfs_driver.h') -Raw
$core = Get-Content -LiteralPath (Join-Path $root 'core\extfs.c') -Raw
$coreHeader = Get-Content -LiteralPath (Join-Path $root 'include\extfs\extfs.h') -Raw
foreach ($token in @('VolumeLockFileObject','VPB_LOCKED','ExtfsLockMountedVolume','ExtfsUnlockMountedVolume','ExtfsDismountLockedVolume','FSCTL_DISMOUNT_VOLUME','NameStatus')) {
    if ($driver -notmatch [regex]::Escape($token) -and $header -notmatch [regex]::Escape($token)) { throw "Missing filesystem contract: $token" }
}
if ($coreHeader -notmatch '#define EXTFS_VERSION_PATCH 3') { throw 'Portable core version is not 0.9.3.' }
if ($core -notmatch 'EXTFS_ERR_NO_SPACE:\s*return "no space left on device"') { throw 'NO_SPACE status text is missing.' }
Write-Host 'Filesystem lifecycle/name/version contracts: PASS'
''')
