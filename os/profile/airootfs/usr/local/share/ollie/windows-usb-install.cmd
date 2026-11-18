@echo off
rem Ollie OS: puts Windows on a drive Windows Setup will not install to (one
rem connected by USB). Ollie OS's ollie-windows-setup puts this script into
rem Windows Setup's start-up image (boot.wim) in place of Setup itself, so it
rem runs by itself when the computer starts from "Install Windows".
rem
rem What it does: finds the empty NTFS part Ollie OS made for Windows (it has a
rem file called OLLIE-WINDOWS-TARGET) and Windows Setup's part (a file called
rem ollie-setup-marker), puts Windows on the first with DISM (the way Setup does
rem it, without Setup's check on USB drives), makes Windows start with BCDBOOT,
rem and restarts. Ollie OS then puts Windows on its start-up menu.
title Ollie OS: putting Windows on this drive
color 1F
echo.
echo   Ollie OS is putting Windows on this drive.
echo   It takes several minutes. Do not turn the computer off.
echo.
wpeinit >nul 2>&1
(echo rescan) | diskpart >nul 2>&1

set N=0
:find
set T=
set S=
for %%L in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist %%L:\OLLIE-WINDOWS-TARGET set T=%%L:
    if exist %%L:\ollie-setup-marker set S=%%L:
)
if defined T if defined S goto found
set /a N+=1
if %N% GEQ 40 goto notfound
ping -n 3 127.0.0.1 >nul
goto find

:found
set LOG=%S%\ollie-install.log
>>%LOG% echo [%date% %time%] Windows goes on %T% (Windows files on %S%)
echo   Windows goes on %T%   (Windows files are on %S%)
set IDX=1
if exist %S%\ollie-image-index.txt for /f "usebackq delims=" %%I in ("%S%\ollie-image-index.txt") do set IDX=%%I
echo   Edition number: %IDX%
echo.
:apply_which
rem The image is on the part Windows goes on (Ollie OS put it there: no 4 GB limit of the Setup part).
if exist %T%\ollie-image.swm goto swm
if exist %T%\ollie-image.esd goto esd
if exist %T%\ollie-image.wim goto wim
rem (or, from an older Ollie OS, on the Windows Setup part)
if exist %S%\sources\install.swm goto oldswm
if exist %S%\sources\install.esd goto oldesd
if exist %S%\sources\install.wim goto oldwim
goto noimage

:swm
set DISMARGS=/imagefile:%T%\ollie-image.swm /swmfile:%T%\ollie-image*.swm
goto apply
:esd
set DISMARGS=/imagefile:%T%\ollie-image.esd
goto apply
:wim
set DISMARGS=/imagefile:%T%\ollie-image.wim
goto apply
:oldswm
set DISMARGS=/imagefile:%S%\sources\install.swm /swmfile:%S%\sources\install*.swm
goto apply
:oldesd
set DISMARGS=/imagefile:%S%\sources\install.esd
goto apply
:oldwim
set DISMARGS=/imagefile:%S%\sources\install.wim
goto apply

:apply
rem DISM's scratch folder goes on the target drive: WinPE's own (a small RAM disk) is too small for a whole Windows.
mkdir %T%\ollie-scratch >nul 2>&1
>>%LOG% echo [%time%] dism apply-image %DISMARGS% index %IDX%
dism /apply-image %DISMARGS% /index:%IDX% /applydir:%T%\ /verify /scratchdir:%T%\ollie-scratch /logpath:%S%\ollie-dism.log
set DISMRC=%errorlevel%
>>%LOG% echo [%time%] dism finished with code %DISMRC%
rmdir /s /q %T%\ollie-scratch >nul 2>&1
if not %DISMRC%==0 goto failed
rem The image has done its job: it is not kept on the Windows part.
del /f /q %T%\ollie-image.wim %T%\ollie-image.esd %T%\ollie-image*.swm >nul 2>&1
:applied
rem Whole? The files Windows cannot start without.
set MISSING=
for %%F in (Windows\System32\winload.efi Windows\System32\ntoskrnl.exe Windows\System32\config\SYSTEM Windows\System32\config\SOFTWARE Windows\System32\config\SAM Windows\System32\smss.exe Windows\System32\winlogon.exe Windows\System32\ntdll.dll Windows\explorer.exe) do if not exist %T%\%%F set MISSING=%%F
if defined MISSING goto partial
>>%LOG% echo [%time%] Windows is whole
if not exist %S%\ollie-unattend.xml goto nounattend
echo   Setting Windows up with the account you asked for...
mkdir %T%\Windows\Panther\Unattend >nul 2>&1
copy /y %S%\ollie-unattend.xml %T%\Windows\Panther\Unattend\unattend.xml >nul
copy /y %S%\ollie-unattend.xml %T%\Windows\Panther\unattend.xml >nul
del /f /q %S%\ollie-unattend.xml >nul 2>&1
:nounattend
rem Windows runs this once at the end of its first start: the clock in UTC (like Ollie OS) and no BitLocker.
if not exist "%S%\sources\$OEM$\$$\Setup\Scripts\SetupComplete.cmd" goto nosetupcomplete
mkdir %T%\Windows\Setup\Scripts >nul 2>&1
copy /y "%S%\sources\$OEM$\$$\Setup\Scripts\SetupComplete.cmd" %T%\Windows\Setup\Scripts\SetupComplete.cmd >nul
:nosetupcomplete
echo.
echo   Making Windows start...
bcdboot %T%\Windows /s %S% /f UEFI >>%LOG% 2>&1
if errorlevel 1 goto failed
>>%LOG% echo [%time%] bcdboot done
echo done>%S%\ollie-windows-installed.txt
echo.
echo   Windows is on the drive. The computer restarts into Ollie OS now.
ping -n 8 127.0.0.1 >nul
wpeutil reboot
goto end

:notfound
color 4F
rem (the start-up part can still be told about it: that shows the script did start)
set S=
for %%L in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist %%L:\ollie-setup-marker set S=%%L:
if defined S >>%S%\ollie-install.log echo [%date% %time%] script started, but the room for Windows (OLLIE-WINDOWS-TARGET) was not found. T=%T%
echo.
echo   Could not find the room Ollie OS made for Windows, or the Windows files.
echo   Turn the computer off, start Ollie OS and run the Add Windows Updater again.
goto stop
:noimage
color 4F
echo.
echo   There is no Windows image (install.wim) on the Windows Setup part.
goto stop
:partial
color 4F
>>%LOG% echo [%time%] Windows is NOT whole: %MISSING% is missing
echo.
echo   Windows was only partly copied to the drive: %MISSING% is missing.
echo   (The part for Windows may be too small, or the copy was cut short.)
echo   Turn the computer off, start Ollie OS and run the Add Windows Updater again.
goto stop
:failed
color 4F
>>%LOG% echo [%time%] failed
echo.
echo   Putting Windows on the drive did not work (see above).
echo   What happened is written in ollie-install.log and ollie-dism.log on the Windows Setup part.
echo   Turn the computer off, start Ollie OS and run the Add Windows Updater again.
:stop
echo.
echo   (This window stays open so you can read it.)
:end
