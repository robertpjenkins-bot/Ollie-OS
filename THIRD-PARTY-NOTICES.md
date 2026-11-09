# Ollie OS: other people's work, and the rules for using it

Ollie OS is made by biobro. Its own code (the scripts, the apps' windows, the
installers and the website) is under the MIT License in [LICENSE](LICENSE).

Ollie OS is built from a lot of free software made by other people. This page
says what it hands out that is theirs, under which licence, and where to get
the source code.

## In the Ollie OS ISO and installed system

- **Arch Linux packages.** Ollie OS is built from the packages of
  [Arch Linux](https://archlinux.org), unchanged. Each package keeps its own
  licence (most are free software licences such as the GPL, LGPL, MIT and BSD
  licences). On an Ollie OS computer they are listed in `/usr/share/licenses`.
  Their source code: <https://gitlab.archlinux.org/archlinux/packaging/packages>
  (how each package is built, with links to its source) and
  <https://sources.archlinux.org> (the source files).
- **Bibata cursors** (`bibata-cursor-theme-bin`): GPL-3.0, by Abdulkaiz Khatri,
  <https://github.com/ful1e5/Bibata_Cursor>.
- **Steam** (the `steam` package from Arch Linux's multilib repository): Valve's
  Steam installer, under Valve's own licence, the same package Arch Linux
  hands out. Using Steam means agreeing to Valve's Steam Subscriber Agreement.
- **shim and MokManager** (for Secure Boot): BSD-2-Clause, by Red Hat, Intel
  and the shim authors (signed for Secure Boot by Microsoft and Canonical), <https://github.com/rhboot/shim>. Unchanged
  copies from Ubuntu's `shim-signed` package; the licence and where they came
  from are in `/usr/local/share/ollie/secureboot/` (COPYRIGHT and README).

**Source code on request.** For anything in an Ollie OS ISO or download under
the GPL or LGPL: ask at <https://github.com/robertpjenkins-bot/Ollie-OS/issues>
and you will be sent its source code, for 3 years after that ISO or download
was made.

## In the Ollie OS downloads (Installer, Builder, Drive Writer, updaters)

- The **Linux installer and Builder** carry **xorriso** (GPL-3.0) and
  **unsquashfs** (squashfs-tools, GPL-2.0), with the libraries they need, from
  the computer they were built on. Inside each one (`usr/lib/ollie-build/`),
  `SOURCES.txt` lists every file, its package and version and where its source
  code is, and `licenses/` has the licences.
- Every **AppImage** contains the AppImage runtime (MIT License,
  <https://github.com/AppImage/type2-runtime>).
- The **Windows installer and Builder** (`.exe`) are written in Go; they
  contain Go's standard library (BSD-3-Clause, <https://go.dev/LICENSE>).

## Fetched for you, not handed out by Ollie OS

These come from their makers, when you ask for them, under the makers' own
terms:

- **Windows 10 and 11** come from Microsoft's website. Windows needs its own
  licence (a product key); Ollie OS does not include one.
- **Minecraft** comes from Flathub; playing needs a Minecraft account.
- **Apps and games from Flathub, Steam, Epic and GOG**: each under its own terms.
- **Game covers** (Find covers in Games) are looked up online for the games you
  have.

## Your games

The Games app and its emulators play game files (ROMs, ISOs) that you put in.
Only use games you own or that are free to share, like homebrew games. Ollie OS
does not come with any.

## Names and logos

Ollie OS is not made by, or connected with, Valve, Microsoft, Apple, Mojang,
Dell, Nintendo, Sony, Sega, Epic Games, GOG or Arch Linux. Steam, Steam Deck,
Windows, Mac, Minecraft, Dell, Nintendo, Game Boy, PlayStation, GameCube, Arch
Linux and the other names here are trademarks of their owners, used only to
say what Ollie OS works with. "Built on Arch Linux" means it uses Arch Linux's
packages.

## Pictures

The screenshots and the desktop picture show Ollie OS's own apps. Some show
emoji from Noto Emoji (Apache License 2.0 and SIL Open Font License,
<https://github.com/googlefonts/noto-emoji>).
