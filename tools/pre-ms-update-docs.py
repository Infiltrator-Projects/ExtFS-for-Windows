# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path

p = Path('.github/workflows/windows-wdk-ci.yml')
text = p.read_text()
needle = '      - name: Locate NuGet\n'
check = "      - name: Verify filesystem contracts\n        shell: powershell\n        run: .\\windows\\test\\Test-FilesystemContracts.ps1\n\n"
if check not in text:
    if needle not in text:
        raise SystemExit('Windows WDK CI insertion point missing')
    p.write_text(text.replace(needle, check + needle, 1))

p = Path('docs/FEATURE_SUPPORT.md')
text = p.read_text()
old = '| Volume lock/unlock | Refused | Exclusive lock ownership/enforcement not implemented |'
new = '| Volume lock/unlock | Implemented | Direct volume handle only; lock succeeds only when no ordinary opens or mapped-section FCBs remain; ownership follows the issuing FILE_OBJECT and releases on unlock/cleanup |'
if old in text:
    text = text.replace(old, new, 1)
if 'Locked-volume dismount' not in text:
    text += '\n| Locked-volume dismount | Implemented bounded path | `FSCTL_DISMOUNT_VOLUME` requires the issuing handle to own an ExtFS volume lock; unlocked forced-dismount teardown remains deferred |\n'
if 'Unrepresentable raw ext names' not in text:
    text += '| Unrepresentable raw ext names | Explicit failure | ext permits arbitrary non-NUL name bytes; Windows enumeration surfaces a name-conversion error rather than silently hiding a live entry |\n'
p.write_text(text)
