package main

import (
	"bufio"
	"os"
	"strings"

	"charm.land/lipgloss/v2"
)

// hostDistro is the host's os-release ID (e.g. "linuxmint"), with ID_LIKE kept
// so unknown derivatives can fall back to a parent distro's glyph.
type hostDistro struct {
	ID    string
	Like  []string
	Human string
}

var host = detectHostDistro()

// detectHostDistro reads the host's os-release.
//
// Inside a Distrobox container /etc/os-release describes the *container*
// (ubuntu), not the machine. Distrobox mounts the host root read-only at
// /run/host, so that is checked first — otherwise a host-only app on a Mint
// host would be labelled with the container's distro.
func detectHostDistro() hostDistro {
	for _, p := range []string{"/run/host/etc/os-release", "/etc/os-release"} {
		if d, ok := parseOSRelease(p); ok {
			return d
		}
	}
	return hostDistro{ID: "linux", Human: "linux"}
}

func parseOSRelease(path string) (hostDistro, bool) {
	f, err := os.Open(path)
	if err != nil {
		return hostDistro{}, false
	}
	defer f.Close()

	var d hostDistro
	s := bufio.NewScanner(f)
	for s.Scan() {
		k, v, ok := strings.Cut(s.Text(), "=")
		if !ok {
			continue
		}
		v = strings.Trim(strings.TrimSpace(v), `"'`)
		switch k {
		case "ID":
			d.ID = v
		case "ID_LIKE":
			d.Like = strings.Fields(v)
		case "NAME":
			d.Human = v
		}
	}
	if d.ID == "" {
		return hostDistro{}, false
	}
	if d.Human == "" {
		d.Human = d.ID
	}
	return d, true
}

// Nerd Font logos, written as explicit escapes: these are private-use
// codepoints, and pasting them as literals is fragile — they silently become
// empty strings when they pass through tooling that does not preserve the
// private-use area.
const (
	// Terminals cannot scale a glyph — a cell is a fixed size — so apparent
	// weight is a property of the icon family. Both of these come from the
	// nf-linux block (U+F300–F32F), the same family as the distro logos, so
	// they share their weight.
	//
	// Do not reach for nf-md-docker (U+F0868) to get a heavier logo: it lives
	// in a supplementary plane, and terminals render those PUA codepoints
	// double-width even though wcwidth — and therefore lipgloss.Width —
	// reports 1. That silently shifts every column right of it by one cell.
	glyphTux    = "\uf17c" // nf-linux-tux — the generic fallback
	glyphDocker = "\uf308" // nf-linux-docker
)

// distroGlyph maps an os-release ID to a Nerd Font logo, falling back through
// ID_LIKE and finally to Tux. Only distros whose codepoints are known are
// listed; everything else resolves through ID_LIKE (EndeavourOS and CachyOS to
// Arch, Pop!_OS to Ubuntu) or lands on Tux, which is better than guessing a
// codepoint and rendering tofu.
func distroGlyph(id string, like []string) string {
	glyphs := map[string]string{
		"ubuntu":    "\uf31b",
		"debian":    "\uf306",
		"linuxmint": "\uf30e",
		"arch":      "\uf303",
		"cachyos":   "\uf303", // Arch-family, no logo of its own
		"manjaro":   "\uf312",
		"fedora":    "\uf30a",
		"centos":    "\uf304",
		"opensuse":  "\uf314",
		"gentoo":    "\uf30d",
		"alpine":    "\uf300",
		"nixos":     "\uf313",
	}
	if id != "" {
		if g, ok := glyphs[id]; ok {
			return g
		}
	}
	for _, l := range like {
		if g, ok := glyphs[l]; ok {
			return g
		}
	}
	// Unknown, undetected, or a distro with no logo: generic Linux.
	return glyphTux
}

// shortDistro trims an os-release ID to something that fits a narrow column.
func shortDistro(id string) string {
	switch id {
	case "linuxmint":
		return "mint"
	case "endeavouros":
		return "endeavour"
	case "opensuse-tumbleweed", "opensuse-leap":
		return "opensuse"
	}
	return id
}

// appGlyph is the marker shown beside an app's name: the container runtime for
// containerised apps, or the host's own distro logo for host-only ones, whose
// payload lands on the host itself.
//
// It sits with the name rather than in its own column: the value is a fixed
// property of the app, not live state like IMAGE and BOX, so it does not earn
// a column of its own.
func (i iconSet) appGlyph(a App) (string, lipgloss.Style) {
	if a.HostOnly {
		if i.nerd {
			return distroGlyph(host.ID, host.Like), styGlyph
		}
		return "⌂", styGlyph
	}
	if i.nerd {
		return glyphDocker, styGlyph
	}
	return "◆", styGlyph
}
