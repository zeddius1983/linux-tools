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

// distroGlyph maps an os-release ID to a Nerd Font logo, falling back through
// ID_LIKE and finally to the Tux glyph. Rolling derivatives (CachyOS,
// EndeavourOS, …) mostly have no logo of their own, which is exactly what
// ID_LIKE is for.
func distroGlyph(id string, like []string) string {
	glyphs := map[string]string{
		"ubuntu":      "",
		"debian":      "",
		"linuxmint":   "",
		"arch":        "",
		"cachyos":     "", // Arch-family, no logo of its own
		"manjaro":     "",
		"endeavouros": "",
		"fedora":      "",
		"rhel":        "",
		"centos":      "",
		"opensuse":    "",
		"gentoo":      "",
		"alpine":      "",
		"nixos":       "",
		"void":        "",
		"pop":         "",
		"elementary":  "",
		"kali":        "",
		"raspbian":    "",
	}
	if g, ok := glyphs[id]; ok {
		return g
	}
	for _, l := range like {
		if g, ok := glyphs[l]; ok {
			return g
		}
	}
	return "" // Tux
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

// platform renders the PLATFORM column: which machine an app actually runs on.
// Containerised apps report the container runtime; host-only apps report the
// host's distro, since that is where their payload lands.
func (i iconSet) platform(a App) (string, lipgloss.Style) {
	if a.HostOnly {
		g := ""
		if i.nerd {
			g = distroGlyph(host.ID, host.Like) + " "
		}
		return g + shortDistro(host.ID), styWarn
	}
	g := ""
	if i.nerd {
		g = " " // nf-dev-docker
	}
	return g + "container", styDesc
}
