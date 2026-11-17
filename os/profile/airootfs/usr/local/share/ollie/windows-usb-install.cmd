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
echo   Windows goes on %T%   (Windows files are on %S%)
set IDX=1
if exist %S%\ollie-image-index.txt for /f "usebackq delims=" %%I in ("%S%\ollie-image-index.txt") do set IDX=%%I
echo   Edition number: %IDX%
echo.
if exist %S%\sources\install.swm goto swm
if exist %S%\sources\install.esd goto esd
if exist %S%\sources\install.wim goto wim
goto noimage

:swm
dism /apply-image /imagefile:%S%\sources\install.swm /swmfile:%S%\sources\install*.swm /index:%IDX% /applydir:%T%\
goto applied
:esd
dism /apply-image /imagefile:%S%\sources\install.esd /index:%IDX% /applydir:%T%\
goto applied
:wim
dism /apply-image /imagefile:%S%\sources\install.wim /index:%IDX% /applydir:%T%\
goto applied

:applied
if errorlevel 1 goto failed
if not exist %T%\Windows\System32\winload.efi goto failed
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
bcdboot %T%\Windows /s %S% /f UEFI
if errorlevel 1 goto failed
echo done>%S%\ollie-windows-installed.txt
echo.
echo   Windows is on the drive. The computer restarts into Ollie OS now.
ping -n 8 127.0.0.1 >nul
wpeutil reboot
goto end

:notfound
color 4F
echo.
echo   Could not find the room Ollie OS made for Windows, or the Windows files.
echo   Turn the computer off, start Ollie OS and run the Add Windows Updater again.
goto stop
:noimage
color 4F
echo.
echo   There is no Windows image (install.wim) on the Windows Setup part.
goto stop
:failed
color 4F
echo.
echo   Putting Windows on the drive did not work (see above).
echo   Turn the computer off, start Ollie OS and run the Add Windows Updater again.
:stop
echo.
echo   (This window stays open so you can read it.)
:end
