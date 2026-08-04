package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseOSRelease(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "os-release")
	os.WriteFile(p, []byte(`NAME="Linux Mint"
ID=linuxmint
ID_LIKE="ubuntu debian"
PRETTY_NAME="Linux Mint 22.3"
`), 0o644)

	d, ok := parseOSRelease(p)
	if !ok {
		t.Fatal("expected parse to succeed")
	}
	if d.ID != "linuxmint" {
		t.Errorf("ID = %q, want linuxmint", d.ID)
	}
	if len(d.Like) != 2 || d.Like[0] != "ubuntu" {
		t.Errorf("ID_LIKE = %v, want [ubuntu debian]", d.Like)
	}
	if _, ok := parseOSRelease(filepath.Join(dir, "nope")); ok {
		t.Error("missing file should not parse")
	}
}

// A distro with no logo of its own must fall back through ID_LIKE rather than
// dropping straight to Tux — this is what makes CachyOS, EndeavourOS and other
// rolling derivatives show an Arch logo.
func TestDistroGlyphFallsBackThroughIDLike(t *testing.T) {
	arch := distroGlyph("arch", nil)
	if got := distroGlyph("some-arch-derivative", []string{"arch"}); got != arch {
		t.Errorf("ID_LIKE fallback = %q, want the arch glyph %q", got, arch)
	}
	if distroGlyph("linuxmint", nil) == "" {
		t.Error("linuxmint should have its own glyph")
	}
	tux := distroGlyph("nothing-like-this", nil)
	if tux == "" || tux == arch {
		t.Errorf("unknown distro should fall back to Tux, got %q", tux)
	}
}

func TestShortDistro(t *testing.T) {
	for in, want := range map[string]string{
		"linuxmint":           "mint",
		"opensuse-tumbleweed": "opensuse",
		"arch":                "arch",
	} {
		if got := shortDistro(in); got != want {
			t.Errorf("shortDistro(%q) = %q, want %q", in, got, want)
		}
	}
}

// Containerised apps report the runtime; host-only apps report the host distro.
func TestPlatformColumn(t *testing.T) {
	i := newIconSet(false)
	if got, _ := i.platform(App{Name: "comfyui"}); got != "container" {
		t.Errorf("containerised app platform = %q, want container", got)
	}
	got, _ := i.platform(App{Name: "shell-toolbox", HostOnly: true})
	if got != shortDistro(host.ID) {
		t.Errorf("host-only app platform = %q, want %q", got, shortDistro(host.ID))
	}
}
