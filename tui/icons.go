package main

import (
	"image/color"

	"charm.land/lipgloss/v2"
)

// iconSet supplies the glyphs used across the dashboard.
//
// Two sets are kept. The Nerd Font set uses private-use-area codepoints and
// looks like gh-dash, but renders as tofu on a terminal without a patched
// font. The plain set uses widely-supported Unicode symbols and is selected
// with --ascii, so the dashboard stays readable everywhere.
type iconSet struct {
	nerd bool
}

func newIconSet(nerd bool) iconSet { return iconSet{nerd: nerd} }

// category returns the leading glyph for a category tab, including a trailing
// space. Unknown categories get a neutral marker.
func (i iconSet) category(name string) string {
	if !i.nerd {
		return ""
	}
	switch name {
	case "AI / LLM":
		return " " // bolt
	case "Development":
		return " " // code
	case "System":
		return " " // cogs
	case "Browsers":
		return " " // globe
	case "Communication":
		return " " // comment
	case "Shell":
		return " " // terminal
	default:
		return " " // bars
	}
}

// image renders the IMAGE column for an app.
func (i iconSet) image(a App) (string, lipgloss.Style) {
	if a.HostOnly {
		// Host-only apps have no image and no box. Left blank rather than
		// marked: the platform glyph beside the name already says why, and a
		// marker here reads as a value when there is none.
		return "", styDesc
	}
	if a.HasImage {
		return i.check(), styStatusOK
	}
	return i.cross(), styStatusNo
}

// box renders the BOX column for an app.
func (i iconSet) box(a App) (string, lipgloss.Style) {
	if a.HostOnly {
		return "", styDesc
	}
	switch {
	case a.BoxRunning:
		return i.dotFilled(), styStatusOK
	case a.HasBox:
		return i.dotHollow(), styWarn
	default:
		return i.cross(), styStatusNo
	}
}

// wizMarker is the checkbox (multi-choice) or radio (single-choice) marker in
// a wizard page. Both sets are plain Unicode: these are box-drawing and
// geometric shapes, present in any font, so there is nothing for a Nerd Font
// variant to improve.
func (i iconSet) wizMarker(multi, on bool) string {
	switch {
	case multi && on:
		return "[✓]"
	case multi:
		return "[ ]"
	case on:
		return "(●)"
	default:
		return "( )"
	}
}

// distro returns the Nerd Font glyph for a compatibility badge's distro, or
// the distro's name when there is no patched font (--ascii) or no glyph for it.
//
// Codepoints match apps/claude-code/statusline.sh, which already had to solve
// this — same source as starship's [os.symbols] and p10k's icons.zsh. CachyOS
// has no glyph of its own in any Nerd Font release, so it borrows Arch's, the
// same fallback statusline.sh makes via ID_LIKE.
func (i iconSet) distro(name string) string {
	if !i.nerd {
		return name
	}
	switch name {
	case "Ubuntu":
		return ""
	case "Linux Mint":
		return ""
	case "CachyOS", "Arch", "Arch Linux":
		return ""
	case "Debian":
		return ""
	case "Fedora":
		return ""
	case "openSUSE":
		return ""
	case "NixOS":
		return ""
	case "Alpine":
		return ""
	default:
		// An unmapped distro must still say which one it is; a generic Tux
		// glyph here would be indistinguishable from the next unmapped one.
		return name
	}
}

// distroColour is the distro's brand colour, so the glyphs in a badge row are
// told apart by colour the way the icons on GitHub are. Unmapped distros fall
// back to the panel foreground, which is also what their name renders in.
func (i iconSet) distroColour(name string) color.Color {
	switch name {
	case "Ubuntu":
		return lipgloss.Color("#e95420")
	case "Linux Mint":
		return lipgloss.Color("#87cf3e")
	case "CachyOS":
		return lipgloss.Color("#00c2a0")
	case "Arch", "Arch Linux":
		return lipgloss.Color("#1793d1")
	case "Debian":
		return lipgloss.Color("#d70a53")
	case "Fedora":
		return lipgloss.Color("#51a2da")
	case "openSUSE":
		return lipgloss.Color("#73ba25")
	case "NixOS":
		return lipgloss.Color("#5277c3")
	case "Alpine":
		return lipgloss.Color("#0d597f")
	default:
		return colFg
	}
}

func (i iconSet) check() string {
	if i.nerd {
		return ""
	}
	return "✓"
}

func (i iconSet) cross() string {
	if i.nerd {
		return ""
	}
	return "✗"
}

func (i iconSet) dotFilled() string { return "●" }
func (i iconSet) dotHollow() string { return "○" }
