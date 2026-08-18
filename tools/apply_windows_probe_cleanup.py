# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path

p = Path('windows/test/Test-ExtFS.ps1')
text = p.read_text(encoding='utf-8')
old = '''        } finally {\n            # If an assertion or I/O failure occurs after append/growth, make a\n            # best-effort attempt to restore the original EOF before surfacing\n            # the qualification failure. The volume is still disposable by\n            # policy because a filesystem defect can make restoration fail.\n            $restore = [IO.File]::Open($file.FullName, [IO.FileMode]::Open,\n                [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)\n            try {\n                if ($restore.Length -ne $originalLength) {\n                    $restore.SetLength($originalLength)\n                    $restore.Flush()\n                }\n            } finally {\n                $restore.Dispose()\n            }\n        }'''
new = '''        } finally {\n            # If an assertion or I/O failure occurs after append/growth, make a\n            # best-effort attempt to restore the original EOF. A cleanup error\n            # must not hide the original qualification failure; if the probe\n            # otherwise succeeds, the final length/hash check below still makes\n            # incomplete restoration fatal.\n            try {\n                $restore = [IO.File]::Open($file.FullName, [IO.FileMode]::Open,\n                    [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)\n                try {\n                    if ($restore.Length -ne $originalLength) {\n                        $restore.SetLength($originalLength)\n                        $restore.Flush()\n                    }\n                } finally {\n                    $restore.Dispose()\n                }\n            } catch {\n                Write-Warning "Could not restore the original EOF after the resize probe: $_"\n            }\n        }'''
if old not in text:
    raise SystemExit('expected resize cleanup block not found')
p.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Windows qualification cleanup patched')
