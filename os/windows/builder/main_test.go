package main

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// fakeISO writes a file that looks like an ISO (or not).
func fakeISO(t *testing.T, path string, size int, mark bool, age time.Duration) {
	t.Helper()
	b := make([]byte, size)
	for i := range b {
		b[i] = byte(i*7 + size)
	}
	if mark {
		copy(b[32769:], "CD001")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, b, 0o644); err != nil {
		t.Fatal(err)
	}
	when := time.Now().Add(-age)
	if err := os.Chtimes(path, when, when); err != nil {
		t.Fatal(err)
	}
}

func writeSum(t *testing.T, path string, right bool) {
	t.Helper()
	b, _ := os.ReadFile(path)
	h := sha256.Sum256(b)
	sum := hex.EncodeToString(h[:])
	if !right {
		sum = "0000000000000000000000000000000000000000000000000000000000000000"
	}
	if err := os.WriteFile(path+".sha256", []byte(sum+"  "+filepath.Base(path)+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestFindOllie(t *testing.T) {
	old := minOllieISO
	minOllieISO = 100_000 // the test files are small
	defer func() { minOllieISO = old }()

	home := t.TempDir()
	downloads := filepath.Join(home, "Downloads")
	work := filepath.Join(home, "Ollie-OS-Builder")
	os.MkdirAll(downloads, 0o755)

	if got := findOllie(home, downloads, work); got != "" {
		t.Fatalf("nothing there, but found %q", got)
	}

	// Not an ISO (no CD001), too small, and not named like Ollie OS: none is taken.
	fakeISO(t, filepath.Join(downloads, "ollie-os-2026.11.20-x86_64.iso"), 200_000, false, time.Hour)
	fakeISO(t, filepath.Join(downloads, "ollie-os-2026.11.21-x86_64.iso"), 50_000, true, time.Hour)
	fakeISO(t, filepath.Join(downloads, "archlinux-2026.11.01-x86_64.iso"), 200_000, true, time.Hour)
	if got := findOllie(home, downloads, work); got != "" {
		t.Fatalf("none of these is Ollie OS, but found %q", got)
	}

	// A real one, with no checksum file: used.
	older := filepath.Join(downloads, "ollie-os-2026.11.19-x86_64.iso")
	fakeISO(t, older, 200_000, true, 48*time.Hour)
	if got := findOllie(home, downloads, work); got != older {
		t.Fatalf("wanted %q, got %q", older, got)
	}

	// A newer one on the Desktop wins.
	newer := filepath.Join(home, "Desktop", "ollie-os-2026.11.22-x86_64.iso")
	fakeISO(t, newer, 210_000, true, time.Hour)
	if got := findOllie(home, downloads, work); got != newer {
		t.Fatalf("wanted the newer one %q, got %q", newer, got)
	}

	// The newer one does not match its checksum file: the older one is used.
	writeSum(t, newer, false)
	if got := findOllie(home, downloads, work); got != older {
		t.Fatalf("the damaged newer one must be skipped: wanted %q, got %q", older, got)
	}

	// With the right checksum it is the one again.
	writeSum(t, newer, true)
	if got := findOllie(home, downloads, work); got != newer {
		t.Fatalf("wanted %q, got %q", newer, got)
	}
}
