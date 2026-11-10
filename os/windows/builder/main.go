// Ollie OS Builder for Windows: downloads the official Arch Linux ISO from
// the Arch Linux servers and turns it into Ollie OS, on this PC, with no
// GitHub and no sign-in: the whole Ollie OS recipe is inside this program
// (os/build-from-arch-iso.sh). Then it can put the new ISO on a USB drive.
//
// It works inside Windows' own Linux (WSL 2), in a small Arch Linux of its
// own called "OllieOS-Builder" (Arch Linux's official WSL image), the way
// the Builder does on Linux and a Mac. Without WSL it offers to install it
// (Windows asks to allow changes, then the PC restarts once).
// It takes 1 to 2 hours and about 20 GB of free space. The ISO goes to
// Downloads.
//
//	Ollie-OS-Builder-Windows.exe              build, then offer the USB drive
//	Ollie-OS-Builder-Windows.exe --usb ISO    put ISO on a USB drive (as admin)
package main

import (
	"bufio"
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

//go:embed ollie-os-source.tar.gz
var source []byte

const distro = "OllieOS-Builder"

// Arch Linux's official WSL image, from its own servers.
var wslImages = []string{
	"https://geo.mirror.pkgbuild.com/wsl/latest/archlinux-latest.wsl",
	"https://fastly.mirror.pkgbuild.com/wsl/latest/archlinux-latest.wsl",
	"https://mirror.rackspace.com/archlinux/wsl/latest/archlinux-latest.wsl",
}

var in = bufio.NewReader(os.Stdin)

func main() {
	fmt.Println()
	var err error
	if len(os.Args) == 3 && os.Args[1] == "--usb" {
		fmt.Println("  Ollie OS Builder: putting Ollie OS on a USB drive")
		fmt.Println()
		err = toUSB(os.Args[2])
	} else {
		fmt.Println("  Ollie OS Builder  (builds a brand-new Ollie OS on this PC, 1-2 hours)")
		fmt.Println()
		err = build()
	}
	if err != nil {
		fmt.Println()
		fmt.Println("Error:", err)
	}
	fmt.Println()
	fmt.Print("Press Enter to close.")
	in.ReadString('\n')
}

func say(s string) { fmt.Println("\n==> " + s) }

// wsl runs wsl.exe; its words come out as UTF-8 (WSL_UTF8), not UTF-16.
func wsl(args ...string) *exec.Cmd {
	c := exec.Command("wsl.exe", args...)
	c.Env = append(os.Environ(), "WSL_UTF8=1")
	return c
}

func wslOutput(args ...string) string {
	out, _ := wsl(args...).Output()
	return strings.ReplaceAll(string(out), "\x00", "")
}

func build() error {
	home, _ := os.UserHomeDir()
	work := filepath.Join(home, "Ollie-OS-Builder")
	downloads := filepath.Join(home, "Downloads")
	if err := os.MkdirAll(work, 0o755); err != nil {
		return err
	}

	// --- Windows' Linux ---
	say("Checking Windows' Linux (WSL)")
	if wsl("--status").Run() != nil {
		fmt.Println("  This PC does not have WSL yet: the Builder builds inside it.")
		fmt.Println("  Installing it takes a few minutes; Windows asks to allow changes,")
		fmt.Println("  and then the PC needs to restart once.")
		fmt.Println()
		if a := strings.ToLower(ask("Install WSL now? [Y/n] ")); a == "n" || a == "no" {
			return errors.New("nothing was changed. Run the Builder again to install WSL")
		}
		if err := exec.Command("powershell", "-NoProfile", "-Command",
			"Start-Process -FilePath wsl.exe -ArgumentList '--install','--no-distribution' -Verb RunAs -Wait").Run(); err != nil {
			return errors.New("Windows did not allow installing WSL. Run the Builder again and click Yes")
		}
		fmt.Println()
		fmt.Println("  WSL is installed. Restart the PC, then run the Builder again.")
		return nil
	}

	// --- The Arch Linux to build in ---
	// First one already on this PC: an Arch Linux in WSL (copied, so it is
	// not changed), or an Arch Linux WSL file (archlinux*.wsl or .tar) less
	// than 4 months old in Downloads, on the Desktop, in the home folder or
	// next to this program. Else from the Arch Linux servers.
	if !strings.Contains(wslOutput("--list", "--quiet"), distro) {
		// Asked first: download it (the default), or use a copy on this PC.
		a := strings.ToLower(ask("Download Arch Linux from the Arch Linux servers now (about 150 MB)? [Y/n] (n: use a copy already on this PC) "))
		if a == "n" || a == "no" {
			say("Looking for Arch Linux on this PC")
		} else {
			goto download
		}
		if found := findArch(home, downloads, work); found != "" {
			fmt.Println("  Found it: " + found + " (no download needed).")
			c := wsl("--import", distro, filepath.Join(work, "wsl"), found, "--version", "2")
			c.Stdout, c.Stderr = os.Stdout, os.Stderr
			err := c.Run()
			if strings.HasPrefix(filepath.Base(found), "ollie-arch-copy") {
				os.Remove(found)
			}
			if err != nil {
				fmt.Println("  It did not work (" + err.Error() + "); downloading Arch Linux instead.")
			}
		} else {
			fmt.Println("  None here.")
		}
	}
download:
	if !strings.Contains(wslOutput("--list", "--quiet"), distro) {
		say("Getting Arch Linux from the Arch Linux servers (about 150 MB)")
		img := filepath.Join(work, "archlinux.wsl")
		if err := downloadFirst(wslImages, img); err != nil {
			fmt.Println("  " + err.Error() + "; trying WSL's own Arch Linux instead.")
			c := wsl("--install", "archlinux", "--name", distro, "--no-launch")
			c.Stdout, c.Stderr = os.Stdout, os.Stderr
			if c.Run() != nil {
				return errors.New("could not get Arch Linux. Is the internet connected? Run the Builder again to retry")
			}
		} else {
			c := wsl("--import", distro, filepath.Join(work, "wsl"), img, "--version", "2")
			c.Stdout, c.Stderr = os.Stdout, os.Stderr
			if err := c.Run(); err != nil {
				return fmt.Errorf("WSL could not set up Arch Linux (%v). Is \"Virtual Machine Platform\" on? Run the Builder again", err)
			}
			os.Remove(img)
		}
	}

	// --- The recipe, and the build ---
	src := filepath.Join(work, "ollie-os-source.tar.gz")
	if err := os.WriteFile(src, source, 0o644); err != nil {
		return fmt.Errorf("could not unpack the recipe (is the disk full?): %v", err)
	}
	say("Downloading the Arch Linux ISO and turning it into Ollie OS (1 to 2 hours)")
	fmt.Println("  You can use the PC meanwhile. Closing this window stops the build; running it again carries on.")
	script := `set -e
src="$(wslpath -u "$1")"; dl="$(wslpath -u "$2")"
mkdir -p /root/ollie-src && cd /root/ollie-src
rm -rf os go.mod cmd internal packaging && tar -xzf "$src"
bash os/build-from-arch-iso.sh /root/ollie-from-iso
iso="$(ls -t os/out/ollie-os-*.iso | head -n 1)"
mkdir -p "$dl"
cp -f "$iso" "$dl/"
cp -f "$iso.sha256" "$dl/" 2>/dev/null || true
echo "OLLIE-ISO $(basename "$iso")"`
	c := wsl("-d", distro, "-u", "root", "--", "bash", "-c", script, "bash", src, downloads)
	out, _ := c.StdoutPipe()
	c.Stderr = os.Stderr
	if err := c.Start(); err != nil {
		return fmt.Errorf("could not start the build: %v", err)
	}
	iso := ""
	lines := bufio.NewScanner(out)
	lines.Buffer(make([]byte, 1<<20), 1<<20)
	for lines.Scan() {
		l := lines.Text()
		if strings.HasPrefix(l, "OLLIE-ISO ") {
			iso = strings.TrimPrefix(l, "OLLIE-ISO ")
			continue
		}
		fmt.Println(l)
	}
	if err := c.Wait(); err != nil || iso == "" {
		return errors.New("the build did not finish (see above). Run the Builder again to retry: what was downloaded is kept")
	}
	path := filepath.Join(downloads, iso)
	fmt.Println()
	fmt.Println("==> The new Ollie OS ISO is in Downloads")
	fmt.Println("  Done! The new Ollie OS is in Downloads: " + iso)
	fmt.Println("  (To free its 20 GB later: wsl --unregister " + distro + ")")
	fmt.Println()
	write := false
	for {
		a := strings.ToLower(ask("Ollie OS is ready! Do you want to write it to a drive now? [y/n] "))
		if strings.HasPrefix(a, "y") {
			write = true
			break
		}
		if strings.HasPrefix(a, "n") {
			fmt.Println("  OK! Not written to a drive. The ISO stays in Downloads.")
			break
		}
	}
	if write {
		self, _ := os.Executable()
		q := func(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }
		if err := exec.Command("powershell", "-NoProfile", "-Command",
			"Start-Process -FilePath "+q(self)+" -ArgumentList '--usb',"+q(`"`+path+`"`)+" -Verb RunAs").Run(); err != nil {
			return errors.New("Windows did not allow it to make changes, which writing to a drive needs. Run it again and click Yes")
		}
	}
	return nil
}

// downloadFirst saves the first of urls that downloads whole.
// findArch: an Arch Linux already on this PC to build in, as a file WSL can
// import: a copy of an Arch Linux installed in WSL (exported into work), or
// the newest archlinux*.wsl / archlinux*.tar(.gz) less than 4 months old.
func findArch(home, downloads, work string) string {
	for _, name := range strings.Fields(wslOutput("--list", "--quiet")) {
		if strings.EqualFold(name, "archlinux") || strings.EqualFold(name, "Arch") {
			copyTar := filepath.Join(work, "ollie-arch-copy.tar")
			fmt.Println("  Arch Linux is in WSL here (" + name + "): copying it (yours is not changed)...")
			if wsl("--export", name, copyTar).Run() == nil {
				return copyTar
			}
			os.Remove(copyTar)
		}
	}
	dirs := []string{work, downloads, filepath.Join(home, "Desktop"), home}
	if exe, err := os.Executable(); err == nil {
		dirs = append(dirs, filepath.Dir(exe))
	}
	best, bestTime := "", time.Time{}
	for _, d := range dirs {
		for _, pat := range []string{"archlinux*.wsl", "archlinux*.tar", "archlinux*.tar.gz"} {
			matches, _ := filepath.Glob(filepath.Join(d, pat))
			for _, m := range matches {
				fi, err := os.Stat(m)
				if err != nil || fi.IsDir() || fi.Size() < 50_000_000 || time.Since(fi.ModTime()) > 120*24*time.Hour {
					continue
				}
				if strings.Contains(strings.ToLower(filepath.Base(m)), "bootstrap") {
					continue // the bootstrap has a folder around it: not one WSL can import
				}
				if best == "" || fi.ModTime().After(bestTime) {
					best, bestTime = m, fi.ModTime()
				}
			}
		}
	}
	return best
}

func downloadFirst(urls []string, dest string) error {
	for _, u := range urls {
		r, err := http.Get(u)
		if err != nil || r.StatusCode != 200 {
			if r != nil {
				r.Body.Close()
			}
			continue
		}
		f, err := os.Create(dest + ".part")
		if err != nil {
			r.Body.Close()
			return err
		}
		p := &progress{total: r.ContentLength, start: time.Now()}
		_, err = io.Copy(io.MultiWriter(f, p), r.Body)
		r.Body.Close()
		f.Close()
		fmt.Println()
		if err == nil {
			return os.Rename(dest+".part", dest)
		}
	}
	return errors.New("could not download Arch Linux's WSL image")
}

// --- Onto a USB drive (the same as Ollie OS Installer, from the ISO just built) ---

type disk struct {
	Number       int
	FriendlyName string
	Size         int64
}

func toUSB(iso string) error {
	f, err := os.Open(iso)
	if err != nil {
		return fmt.Errorf("could not open the ISO: %v", err)
	}
	defer f.Close()
	st, _ := f.Stat()
	size := st.Size()
	sum := ""
	if b, err := os.ReadFile(iso + ".sha256"); err == nil {
		if fl := strings.Fields(string(b)); len(fl) > 0 {
			sum = strings.ToLower(fl[0])
		}
	}

	disks, err := usbDisks()
	if err != nil {
		return err
	}
	if len(disks) == 0 {
		return errors.New("no USB drive was found. Plug in a USB drive (8 GB or more), then run this again")
	}
	fmt.Println("==> USB drives (everything on the one you pick is erased)")
	for i, d := range disks {
		fmt.Printf("  %d) %-40s %6.1f GB\n", i+1, d.FriendlyName, float64(d.Size)/1e9)
	}
	fmt.Println()
	n, err := strconv.Atoi(ask(fmt.Sprintf("Put Ollie OS on which drive? [1-%d] ", len(disks))))
	if err != nil || n < 1 || n > len(disks) {
		return errors.New("no such drive; nothing was changed")
	}
	d := disks[n-1]
	if d.Size < size {
		return fmt.Errorf("%s is too small for Ollie OS (it needs %d MB)", d.FriendlyName, size/1000000)
	}
	fmt.Printf("\nEVERYTHING on %s (%.1f GB) will be erased.\n", d.FriendlyName, float64(d.Size)/1e9)
	if ask("Type ERASE to put Ollie OS on it: ") != "ERASE" {
		return errors.New("cancelled; nothing was changed")
	}

	fmt.Println()
	fmt.Println("==> Erasing the drive")
	exec.Command("powershell", "-NoProfile", "-Command",
		fmt.Sprintf("Clear-Disk -Number %d -RemoveData -RemoveOEM -Confirm:$false", d.Number)).Run()
	dev, err := os.OpenFile(fmt.Sprintf(`\\.\PhysicalDrive%d`, d.Number), os.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("could not open the drive (%v). Unplug it, plug it in again, and run this again", err)
	}
	defer dev.Close()

	fmt.Println("==> Writing Ollie OS onto the drive")
	h := sha256.New()
	p := &progress{total: size, start: time.Now()}
	block := make([]byte, 4<<20)
	for {
		k, rerr := io.ReadFull(f, block)
		if k > 0 {
			h.Write(block[:k])
			p.Write(block[:k])
			chunk := block[:k]
			if k%4096 != 0 { // a drive takes whole sectors
				chunk = append(chunk, make([]byte, 4096-k%4096)...)
			}
			if _, err := dev.Write(chunk); err != nil {
				return fmt.Errorf("could not write to the drive: %v", err)
			}
		}
		if rerr == io.EOF || rerr == io.ErrUnexpectedEOF {
			break
		}
		if rerr != nil {
			return fmt.Errorf("could not read the ISO: %v", rerr)
		}
	}
	fmt.Println()
	if sum != "" && hex.EncodeToString(h.Sum(nil)) != sum {
		return errors.New("the ISO is damaged (its checksum does not match). Build it again")
	}
	fmt.Println()
	fmt.Println("  Done: Ollie OS is on the USB drive.")
	fmt.Println()
	fmt.Println("  Start the computer from it: Dell and most PCs, tap F12 (or F11, Esc)")
	fmt.Println("  while it starts; Steam Machine, hold Volume Down; Mac, hold Option.")
	fmt.Println("  (Windows may say the drive needs formatting: say Cancel. That is Ollie OS.)")
	fmt.Println()
	fmt.Println("  Secure Boot on? The first time, a blue screen says \"Verification failed\":")
	fmt.Println("  press Enter, then any key quickly, then pick Enroll key from disk, OLLIE_OS,")
	fmt.Println("  OLLIE-OS-KEY.cer, Continue, Yes, Reboot. Only once on each computer.")
	fmt.Println()
	fmt.Println("  A computer with Windows? Write down its BitLocker recovery key first")
	fmt.Println("  (aka.ms/myrecoverykey): Windows may ask for it after starting from a USB.")
	fmt.Println("  Don't turn Secure Boot off: that makes Windows ask for it for sure.")
	return nil
}

// The USB drives, as Windows sees them (never the one Windows runs from).
func usbDisks() ([]disk, error) {
	out, err := exec.Command("powershell", "-NoProfile", "-Command",
		"@(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsBoot -and -not $_.IsSystem } | Select-Object Number,FriendlyName,Size) | ConvertTo-Json -Compress").Output()
	if err != nil {
		return nil, errors.New("could not list the drives")
	}
	var disks []disk
	s := strings.TrimSpace(string(out))
	if s == "" {
		return nil, nil
	}
	if err := json.Unmarshal([]byte(s), &disks); err != nil {
		var one disk
		if json.Unmarshal([]byte(s), &one) != nil {
			return nil, errors.New("could not read the list of drives")
		}
		disks = []disk{one}
	}
	return disks, nil
}

func ask(q string) string {
	fmt.Print(q)
	s, _ := in.ReadString('\n')
	return strings.TrimSpace(s)
}

type progress struct {
	total, done int64
	last        int
	start       time.Time
}

func (p *progress) Write(b []byte) (int, error) {
	p.done += int64(len(b))
	if p.total > 0 {
		pct := int(p.done * 100 / p.total)
		if pct != p.last {
			p.last = pct
			fmt.Printf("\r  %3d%%  %d of %d MB  (%d min)", pct, p.done/1000000, p.total/1000000, int(time.Since(p.start).Minutes()))
		}
	}
	return len(b), nil
}
