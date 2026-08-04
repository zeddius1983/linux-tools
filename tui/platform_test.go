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

// The name glyph distinguishes containerised from host-only apps, and must
// stay exactly one cell wide so it cannot skew the name column.
func TestAppGlyph(t *testing.T) {
	for _, nerd := range []bool{true, false} {
		i := newIconSet(nerd)
		cont, _ := i.appGlyph(App{Name: "comfyui"})
		hostly, _ := i.appGlyph(App{Name: "shell-toolbox", HostOnly: true})
		if cont == hostly {
			t.Errorf("nerd=%v: container and host-only glyphs must differ", nerd)
		}
		for _, g := range []string{cont, hostly} {
			if n := len([]rune(g)); n != 1 {
				t.Errorf("nerd=%v: glyph %q is %d runes, want 1", nerd, g, n)
			}
		}
	}
}

// When os-release cannot be read or carries no usable ID, the glyph must fall
// back to generic Linux rather than rendering nothing (which silently ate a
// column cell) or tofu.
func TestGlyphFallsBackToGenericLinux(t *testing.T) {
	cases := []struct {
		name string
		id   string
		like []string
	}{
		{"undetected", "", nil},
		{"placeholder id", "linux", nil},
		{"unknown distro", "some-unheard-of-os", nil},
		{"unknown with unknown ID_LIKE", "weird", []string{"also-weird"}},
	}
	for _, c := range cases {
		if got := distroGlyph(c.id, c.like); got != glyphTux {
			t.Errorf("%s: glyph = %q, want the generic Tux glyph %q", c.name, got, glyphTux)
		}
	}
}

// Every glyph must be exactly one cell; an empty string silently collapses the
// name column, which is how the missing Docker glyph slipped through before.
func TestGlyphsAreNonEmpty(t *testing.T) {
	if glyphDocker == "" || glyphTux == "" {
		t.Fatal("glyph constants must not be empty")
	}
	for _, id := range []string{"ubuntu", "arch", "fedora", "linuxmint", "cachyos"} {
		if g := distroGlyph(id, nil); len([]rune(g)) != 1 {
			t.Errorf("distroGlyph(%q) = %q, want exactly 1 rune", id, g)
		}
	}
}
