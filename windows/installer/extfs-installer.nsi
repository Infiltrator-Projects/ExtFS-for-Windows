; SPDX-License-Identifier: GPL-3.0-or-later
Unicode True
RequestExecutionLevel admin
ManifestSupportedOS all

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

Name "ExtFS for Windows 0.9.3 Experimental"
OutFile "ExtFS-for-Windows-0.9.3-experimental-x64-setup.exe"
InstallDir "$PROGRAMFILES64\ExtFS"
BrandingText "ExtFS Project"

VIProductVersion "0.9.3.0"
VIAddVersionKey "ProductName" "ExtFS for Windows"
VIAddVersionKey "CompanyName" "Shannon Smith"
VIAddVersionKey "FileDescription" "ExtFS experimental x64 setup"
VIAddVersionKey "FileVersion" "0.9.3.0"
VIAddVersionKey "LegalCopyright" "Copyright (c) 2026 Shannon Smith"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; Refuse unsupported architectures before presenting the experimental-driver warning.
Function .onInit
    ${IfNot} ${RunningX64}
        MessageBox MB_ICONSTOP "This package requires 64-bit Intel/AMD Windows."
        Abort
    ${EndIf}
    MessageBox MB_ICONEXCLAMATION|MB_OKCANCEL \
        "ExtFS 0.9.3 is an unvalidated kernel-driver checkpoint. Use it only in a disposable Windows VM with a backed-up test volume. It supports same-size data overwrites on eligible ext2/ext3/ext4 volumes, direct-block growth/truncation on ext2, bounded journaled direct-file growth/truncation on clean eligible ext3 volumes, and checksum-aware ext4 resize using either the inline root or one external leaf behind a depth-1 root. Deeper or multi-leaf extent-tree mutation, 64-bit/flex_bg allocation, create/delete/rename and dirty-journal replay remain refused. A driver defect can still crash Windows.$\r$\n$\r$\nContinue?" \
        IDOK continue
    Abort
continue:
FunctionEnd

; Stage the driver, certificate and PowerShell lifecycle scripts, then let the
; PowerShell installer perform the privileged service/certificate operations.
Section "Install ExtFS" SecMain
    SetRegView 64
    ${DisableX64FSRedirection}
    SetOutPath "$INSTDIR"
    File "..\..\release\driver\extfs.sys"
    File "..\..\release\driver\extfs.inf"
    File "..\..\release\driver\extfs.cat"
    File "..\..\release\driver\extfs-test.cer"
    File "Install-ExtFS.ps1"
    File "Uninstall-ExtFS.ps1"
    File "..\..\docs\WINDOWS_BUILD.md"
    WriteUninstaller "$INSTDIR\Uninstall-ExtFS.exe"

    nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\Install-ExtFS.ps1"'
    Pop $0
    Pop $1
    ; Exit 3010 is deliberate: TESTSIGNING was enabled and Windows must reboot
    ; before this same setup can load the test-signed filesystem driver.
    ${If} $0 == 3010
        SetRebootFlag true
        MessageBox MB_ICONINFORMATION|MB_OK \
            "Windows test-signing mode was enabled. Restart Windows, then run this setup again to install and load ExtFS."
        Quit
    ${ElseIf} $0 != 0
        MessageBox MB_ICONSTOP|MB_OK "ExtFS installation failed (exit $0).$\r$\n$\r$\n$1"
        Abort
    ${EndIf}

    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS" \
        "DisplayName" "ExtFS for Windows 0.9.3 Experimental"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS" \
        "UninstallString" '"$INSTDIR\Uninstall-ExtFS.exe"'
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS" \
        "Publisher" "Shannon Smith"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS" \
        "DisplayVersion" "0.9.3"
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS" \
        "NoModify" 1
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS" \
        "NoRepair" 1
    ${EnableX64FSRedirection}
SectionEnd

Section "Uninstall"
    SetRegView 64
    ${DisableX64FSRedirection}
    nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\Uninstall-ExtFS.ps1"'
    Delete /REBOOTOK "$SYSDIR\drivers\extfs.sys"
    Delete "$INSTDIR\extfs.sys"
    Delete "$INSTDIR\extfs.inf"
    Delete "$INSTDIR\extfs.cat"
    Delete "$INSTDIR\extfs-test.cer"
    Delete "$INSTDIR\Install-ExtFS.ps1"
    Delete "$INSTDIR\Uninstall-ExtFS.ps1"
    Delete "$INSTDIR\WINDOWS_BUILD.md"
    Delete "$INSTDIR\Uninstall-ExtFS.exe"
    RMDir /REBOOTOK "$INSTDIR"
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS"
    ${EnableX64FSRedirection}
SectionEnd
