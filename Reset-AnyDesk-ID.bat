@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION
TITLE Reset AnyDesk ID

:: ===========================================================================
::  Generate A New AnyDesk ID  -  fixed build for Windows 10 / 11 / Server
::
::  Fixes applied to the original script:
::    1. WMIC was removed in Windows 11 24H2+, so "WMIC OS GET OSArchitecture"
::       failed and the script always ended with "OS architecture is not
::       supported". WMIC is no longer used at all: the AnyDesk installation
::       is located from the service registration and the default folders.
::    2. Labels must not start with a digit (:64BIT / :32BIT) - renamed.
::    3. The progress bar printed spaces for both the filled and the empty
::       part, so nothing was ever visible - fixed.
::    4. AnyDesk installed outside the hard-coded folders is now found.
::    5. Service detection handles both "AnyDesk" and "AnyDeskMSI".
::    6. Temporary files in %WinDir%\Temp are no longer needed at all.
::    7. Fixed the nested IF/ELSE parsing of the architecture decision, the
::       append (>>) on scratch files and the user-profile enumeration.
::
::  Run this file as Administrator (right click -> Run as administrator).
:: ===========================================================================

COLOR 0C

ECHO.
ECHO H   H  EEEEE  X   X   CCCCC  OOO   DDDD   EEEEE
ECHO H   H  E       X X   C      O   O  D   D  E
ECHO HHHHH  EEEE     X    C      O   O  D   D  EEEE
ECHO H   H  E       X X   C      O   O  D   D  E
ECHO H   H  EEEEE  X   X   CCCCC  OOO   DDDD   EEEEE
ECHO.

:: -------------------------
:: Administrator check
:: -------------------------
SET "ISADMIN="
FLTMC.exe >NUL 2>&1
IF NOT ERRORLEVEL 1 SET "ISADMIN=1"
IF NOT DEFINED ISADMIN (
    NET SESSION >NUL 2>&1
    IF NOT ERRORLEVEL 1 SET "ISADMIN=1"
)
IF NOT DEFINED ISADMIN (
    ECHO.
    ECHO ERROR: This script must be run as Administrator.
    ECHO        Right-click the .bat file and choose "Run as administrator".
    ECHO.
    PAUSE
    EXIT /B 1
)

COLOR 0A

:: -------------------------
:: Environment
:: -------------------------
SET /A total=7
SET "PF86=%ProgramFiles(x86)%"
SET "SVC="
SET "ADEXE="
SET "RAWPATH="
SET "ARCH="
IF /I "%PROCESSOR_ARCHITECTURE%"=="AMD64"   SET "ARCH=64-bit"
IF /I "%PROCESSOR_ARCHITECTURE%"=="ARM64"   SET "ARCH=ARM64"
IF /I "%PROCESSOR_ARCHITEW6432%"=="AMD64"   SET "ARCH=64-bit"
IF NOT DEFINED ARCH SET "ARCH=32-bit"

CALL :ShowProgress 0 "Initializing..."

:: -------------------------
:: Locate the AnyDesk service (AnyDesk or the MSI variant AnyDeskMSI)
:: -------------------------
FOR %%S IN (AnyDesk AnyDeskMSI) DO IF NOT DEFINED SVC (
    SC.exe query %%S >NUL 2>&1
    IF NOT ERRORLEVEL 1 SET "SVC=%%S"
)
IF NOT DEFINED SVC SET "SVC=AnyDesk"

:: -------------------------
:: 1) Stop and disable the AnyDesk service
:: -------------------------
@ECHO Disabling the AnyDesk service...
SC.exe failure "%SVC%" reset= 0 actions= "" >NUL 2>&1
SC.exe config "%SVC%" start= disabled >NUL 2>&1
SC.exe stop "%SVC%" >NUL 2>&1

SET /A "wait=0"
:WAITSVC
SC.exe query "%SVC%" 2>NUL | FIND.exe /I "STOPPED" >NUL
IF NOT ERRORLEVEL 1 GOTO :SVCGONE
SET /A "wait+=1"
IF !wait! GEQ 10 GOTO :SVCGONE
CALL :Sleep 1
GOTO :WAITSVC
:SVCGONE
CALL :ShowProgress 1 "AnyDesk service disabled"

:: -------------------------
:: 2) Kill any running AnyDesk process
:: -------------------------
@ECHO Killing the AnyDesk process...
TASKKILL.exe /F /IM AnyDesk.exe /T >NUL 2>&1
TASKKILL.exe /F /IM AnyDeskMSI.exe /T >NUL 2>&1
CALL :ShowProgress 2 "AnyDesk process terminated"

:: -------------------------
:: 3) Delete the machine-wide settings (this is what resets the ID)
:: -------------------------
@ECHO Deleting AnyDesk settings in ProgramData...
CALL :ForceDelete "%ProgramData%\AnyDesk"
CALL :ForceDelete "%ProgramData%\AnyDeskMSI"
IF EXIST "%ProgramData%\AnyDesk\service.conf" (
    @ECHO WARNING: "%ProgramData%\AnyDesk" could not be fully deleted.
    @ECHO          The ID will only change if this folder is removed.
)
CALL :ShowProgress 3 "ProgramData settings deleted"

:: -------------------------
:: 4) Delete the per-user settings of every local profile
:: -------------------------
@ECHO Deleting AnyDesk settings in local user accounts...
FOR /D %%U IN ("%SystemDrive%\Users\*") DO CALL :CleanProfile "%%~fU"
CALL :ShowProgress 4 "User account settings deleted"

:: -------------------------
:: 5) Re-enable and start the AnyDesk service
:: -------------------------
@ECHO Enabling the AnyDesk service...
SC.exe config "%SVC%" start= auto >NUL 2>&1
SC.exe failure "%SVC%" reset= 0 actions= restart/0/restart/0/restart/0 >NUL 2>&1
SC.exe start "%SVC%" >NUL 2>&1
CALL :ShowProgress 5 "AnyDesk service enabled"

:: -------------------------
:: 6) Locate the AnyDesk executable (no WMIC, no hard-coded architecture)
:: -------------------------
@ECHO Detecting the AnyDesk installation...
CALL :FindAnyDesk
IF DEFINED ADEXE (
    CALL :ShowProgress 6 "!ARCH! - AnyDesk located"
) ELSE (
    CALL :ShowProgress 6 "!ARCH! - AnyDesk not located yet"
)

:: -------------------------
:: 7) Start AnyDesk so it generates the new ID
:: -------------------------
IF NOT DEFINED ADEXE GOTO :ADINF
@ECHO Starting the AnyDesk process...
START "" "%ADEXE%"
CALL :WaitForNewId
IF EXIST "%ProgramData%\AnyDesk\service.conf" (
    CALL :ShowProgress 7 "New AnyDesk ID generated"
) ELSE (
    CALL :ShowProgress 7 "AnyDesk started"
)
GOTO :END

:: -------------------------
:: AnyDesk not found in a known location
:: -------------------------
:ADINF
@ECHO.
@ECHO +===================================================================+
@ECHO ^| The AnyDesk settings were reset, but the program was not found   ^|
@ECHO ^| in a known location. Start AnyDesk manually (it will create the  ^|
@ECHO ^| new ID) or reinstall it.                                         ^|
@ECHO +===================================================================+
PAUSE
GOTO :END

:: -------------------------
:: End
:: -------------------------
:END
@ECHO.
IF EXIST "%ProgramData%\AnyDesk\service.conf" (
    @ECHO Done! A new AnyDesk ID has been generated.
    @ECHO Check the ID shown in the AnyDesk window.
) ELSE (
    @ECHO AnyDesk settings were reset. Start AnyDesk to generate the new ID.
)
COLOR 07
CALL :Sleep 3
ENDLOCAL
PAUSE
EXIT /B 0


:: ===========================================================================
::  Subroutines
:: ===========================================================================

:: -------------------------
:: Progress bar: :ShowProgress <step> <message>
:: -------------------------
:ShowProgress
SET /A "step=%~1"
SET "message=%~2"
SET /A "percent=(step*100)/total"
SET /A "bars=(step*50)/total"
SET /A "empty=50-bars"
<NUL SET /P "=Progress: ["
FOR /L %%I IN (1,1,!bars!) DO <NUL SET /P "=#"
FOR /L %%I IN (1,1,!empty!) DO <NUL SET /P "=."
<NUL SET /P "=] !percent!%% - !message!"
ECHO.
CALL :Sleep 1
GOTO :EOF

:: -------------------------
:: Delete a per-user AnyDesk folder: :CleanProfile <profile folder>
:: -------------------------
:CleanProfile
IF NOT EXIST "%~1\AppData\Roaming\AnyDesk" GOTO :EOF
CALL :ForceDelete "%~1\AppData\Roaming\AnyDesk"
IF NOT EXIST "%~1\AppData\Local\AnyDesk" GOTO :EOF
CALL :ForceDelete "%~1\AppData\Local\AnyDesk"
GOTO :EOF

:: -------------------------
:: Take ownership, grant access and delete a folder: :ForceDelete <folder>
:: -------------------------
:ForceDelete
IF NOT EXIST "%~1" GOTO :EOF
TAKEOWN.exe /F "%~1" /A /R /D Y >NUL 2>&1
ICACLS.exe "%~1" /T /C /Q /RESET >NUL 2>&1
ICACLS.exe "%~1" /T /C /Q /GRANT "*S-1-5-32-544:F" "*S-1-5-18:F" >NUL 2>&1
RMDIR "%~1" /S /Q >NUL 2>&1
IF NOT EXIST "%~1" GOTO :EOF
ATTRIB.exe -R -H -S "%~1" /S /D >NUL 2>&1
TAKEOWN.exe /F "%~1" /A /R /D Y >NUL 2>&1
ICACLS.exe "%~1" /T /C /Q /RESET >NUL 2>&1
ICACLS.exe "%~1" /T /C /Q /GRANT "*S-1-5-32-544:F" "*S-1-5-18:F" >NUL 2>&1
RMDIR "%~1" /S /Q >NUL 2>&1
GOTO :EOF

:: -------------------------
:: Find AnyDesk.exe: service ImagePath, then the default install folders
:: -------------------------
:FindAnyDesk
SET "ADEXE="
SET "RAWPATH="
IF DEFINED SVC (
    FOR /F "tokens=2,*" %%A IN ('REG.exe QUERY "HKLM\SYSTEM\CurrentControlSet\Services\%SVC%" /V ImagePath 2^>NUL ^| FIND.exe /I "ImagePath"') DO SET "RAWPATH=%%B"
)
IF DEFINED RAWPATH CALL :TryPath "%RAWPATH:"=%"
SET "RAWPATH="
IF NOT DEFINED ADEXE IF EXIST "%PF86%\AnyDesk\AnyDesk.exe" SET "ADEXE=%PF86%\AnyDesk\AnyDesk.exe"
IF NOT DEFINED ADEXE IF EXIST "%ProgramFiles%\AnyDesk\AnyDesk.exe" SET "ADEXE=%ProgramFiles%\AnyDesk\AnyDesk.exe"
IF NOT DEFINED ADEXE IF EXIST "%SystemDrive%\Program Files (x86)\AnyDesk\AnyDesk.exe" SET "ADEXE=%SystemDrive%\Program Files (x86)\AnyDesk\AnyDesk.exe"
IF NOT DEFINED ADEXE IF EXIST "%SystemDrive%\Program Files\AnyDesk\AnyDesk.exe" SET "ADEXE=%SystemDrive%\Program Files\AnyDesk\AnyDesk.exe"
IF NOT DEFINED ADEXE FOR /F "delims=" %%P IN ('WHERE.exe AnyDesk.exe 2^>NUL') DO IF NOT DEFINED ADEXE SET "ADEXE=%%P"
GOTO :EOF

:: -------------------------
:: Accept a full command line from the service ImagePath: :TryPath <"path" args>
:: -------------------------
:TryPath
SET "D=%~dp1"
IF NOT DEFINED ADEXE IF EXIST "%D%AnyDesk.exe" SET "ADEXE=%D%AnyDesk.exe"
GOTO :EOF

:: -------------------------
:: Wait (max 15 s) for the regenerated configuration file
:: -------------------------
:WaitForNewId
SET /A "vwait=0"
:WAITCONF
IF EXIST "%ProgramData%\AnyDesk\service.conf" GOTO :EOF
SET /A "vwait+=1"
IF !vwait! GEQ 15 GOTO :EOF
CALL :Sleep 1
GOTO :WAITCONF

:: -------------------------
:: Console-independent delay: :Sleep <seconds>
:: (TIMEOUT fails when there is no console input handle)
:: -------------------------
:Sleep
TIMEOUT /T %~1 /NOBREAK >NUL 2>&1
IF NOT ERRORLEVEL 1 GOTO :EOF
SET /A "pdelay=%~1+1"
PING.exe -n !pdelay! 127.0.0.1 >NUL 2>&1
GOTO :EOF
