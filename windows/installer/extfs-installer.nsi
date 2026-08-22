; SPDX-License-Identifier: GPL-3.0-or-later
Unicode True
RequestExecutionLevel admin
ManifestSupportedOS all

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

!ifndef TARGET_ARCH
!define TARGET_ARCH "x64"
!endif

!if "${TARGET_ARCH}" S== "ARM64"
!define EXPECTED_MACHINE_ARCH "ARM64"
!define ARCH_SLUG "arm64"
!else if "${TARGET_ARCH}" S== "x64"
!define EXPECTED_MACHINE_ARCH "AMD64"
!define ARCH_SLUG "x64"
!else
!error "TARGET_ARCH must be x64 or ARM64"
!endif

Name "ExtFS for Windows 0.9.4 Experimental (${TARGET_ARCH})"
OutFile "ExtFS-for-Windows-0.9.4-experimental-${ARCH_SLUG}-setup.exe"
InstallDir "$PROGRAMFILES64\ExtFS"
BrandingText "ExtFS Project"

VIProductVersion "0.9.4.0"
VIAddVersionKey "ProductName" "ExtFS for Windows"
VIAddVersionKey "CompanyName" "Shannon Smith"
VIAddVersionKey "FileDescription" "ExtFS experimental ${TARGET_ARCH} setup"
VIAddVersionKey "FileVersion" "0.9.4.0"
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

; Refuse a driver/host architecture mismatch before showing the warning.
Function .onInit
    nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "if ([Environment]::GetEnvironmentVariable(''PROCESSOR_ARCHITECTURE'',''Machine'') -eq ''${EXPECTED_MACHINE_ARCH}'') { exit 0 } else { exit 1 }"'
    Pop $0
    Pop $1
    ${If} $0 != 0
        MessageBox MB_ICONSTOP "This package requires native ${TARGET_ARCH} Windows. It cannot install a kernel driver on a different architecture."
        Abort
    ${EndIf}
    MessageBox MB_ICONEXCLAMATION|MB_OKCANCEL \
        "ExtFS 0.9.4 is a test-only kernel-driver checkpoint. This release is an installer hotfix carrying the already-qualified 0.9.3 driver payload. Use it only on a disposable test system and a fully backed-up test volume. Start with read-only access. A driver defect can crash Windows or corrupt data.$\r$\n$\r$\nContinue?" \
        IDOK continue
    Abort
continue:
FunctionEnd

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
    File "..\test\Test-HostReadiness.ps1"
    File "..\..\docs\WINDOWS_BUILD.md"
    File "..\..\docs\ARM64_TESTING.md"
    WriteUninstaller "$INSTDIR\Uninstall-ExtFS.exe"

    nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\Install-ExtFS.ps1" -TargetArchitecture "${TARGET_ARCH}"'
    Pop $0
    Pop $1
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
        "DisplayName" "ExtFS for Windows 0.9.4 Experimental (${TARGET_ARCH})"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS" \
        "UninstallString" '"$INSTDIR\Uninstall-ExtFS.exe"'
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS" \
        "Publisher" "Shannon Smith"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS" \
        "DisplayVersion" "0.9.4"
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
    Delete "$INSTDIR\Test-HostReadiness.ps1"
    Delete "$INSTDIR\WINDOWS_BUILD.md"
    Delete "$INSTDIR\ARM64_TESTING.md"
    Delete "$INSTDIR\Uninstall-ExtFS.exe"
    RMDir /REBOOTOK "$INSTDIR"
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ExtFS"
    ${EnableX64FSRedirection}
SectionEnd
