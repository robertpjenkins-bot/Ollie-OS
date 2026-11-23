**Ollie OS 1.9**: the fun gaming computer, made by biobro.

**New in 1.9**
- **The Mac installer works on Macs with an Apple chip** (M1, M2, M3, M4) and on Intel Macs. It makes the USB drive in 10 to 30 minutes. (A Mac with an Apple chip makes the drive; Ollie OS itself starts on the Steam Deck, Steam Machine, a PC or an Intel Mac.)
- **The installers look in your Downloads folder first.** If the Ollie OS file (ollie-os-...iso) is already there, there is no second download and no 1 to 2 hour build.
- The birthday hello on 23 November no longer covers the first-start windows, and Enter closes it.
- Ollie OS says 1.9 in its Welcome window.

**Downloads**
- **Ollie-OS-Installer-Mac.dmg** (or **Ollie-OS-Installer-Mac.zip**): the Mac installer.
- **Ollie-OS-Installer-Windows.exe**: the Windows installer.
- **Ollie-OS-Installer-x86_64.AppImage**: the Linux installer (Linux, SteamOS, Steam Deck desktop mode).
- **Ollie-OS-Latest-Updater-x86_64.AppImage**: the Linux updater. Open it on an Ollie OS you already have to bring it up to 1.9.
- **ollie-os-...-x86_64.iso** and its **.sha256**: the whole Ollie OS. The Mac installer downloads this; you can also write it to a USB drive with any ISO writer (balenaEtcher, Rufus).

**Mac: if the .dmg will not open**, open Terminal (Command + Space, type Terminal) and paste this one line:
bash <(curl -fsSL https://raw.githubusercontent.com/robertpjenkins-bot/Ollie-OS/claude/fervent-gates-cs7smv/os/usb/mac/ollie-mac-install.sh)

**Starting from the drive:** Steam Deck and Steam Machine, hold Volume Down; Dell and most PCs, tap F12; Intel Mac, hold Option.
