package main

import "charm.land/lipgloss/v2"

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
		return i.check() + " built", styStatusOK
	}
	return i.cross() + " —", styStatusNo
}

// box renders the BOX column for an app.
func (i iconSet) box(a App) (string, lipgloss.Style) {
	if a.HostOnly {
		return "", styDesc
	}
	switch {
	case a.BoxRunning:
		return i.dotFilled() + " running", styStatusOK
	case a.HasBox:
		return i.dotHollow() + " stopped", styWarn
	default:
		return i.cross() + " —", styStatusNo
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
