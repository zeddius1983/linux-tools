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

// superscriptLetters renders text with Unicode modifier letters, matching the
// superscript tab counts. Unlike digits, not every letter has a superscript
// form (q has none, i and others are inconsistent across fonts), so this
// reports false and the caller falls back to plain text rather than emitting a
// half-superscripted word.
func superscriptLetters(s string) (string, bool) {
	forms := map[rune]rune{
		'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ', 'f': 'ᶠ', 'g': 'ᵍ',
		'h': 'ʰ', 'i': 'ⁱ', 'j': 'ʲ', 'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ',
		'o': 'ᵒ', 'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ', 'v': 'ᵛ',
		'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
	}
	var out []rune
	for _, c := range s {
		f, ok := forms[c]
		if !ok {
			return s, false
		}
		out = append(out, f)
	}
	return string(out), true
}

// hostBadge marks a host-only app next to its name. Host-only is a trait of 3
// of 23 apps, so it is encoded as a badge rather than a column that would be
// blank on almost every row.
//
// Superscript keeps it to 4 cells, which matters because the badge competes
// with the app label for width on exactly the rows that carry it.
func (i iconSet) hostBadge() string {
	if b, ok := superscriptLetters("host"); ok {
		return b
	}
	return "host"
}

// image renders the IMAGE column for an app.
func (i iconSet) image(a App) (string, lipgloss.Style) {
	if a.HostOnly {
		// Host-only apps genuinely have no image and no box; the badge on the
		// name says why, so these read as "not applicable", not "not built".
		return i.dash(), styDesc
	}
	if a.HasImage {
		return i.check() + " built", styStatusOK
	}
	return i.cross() + " —", styStatusNo
}

// box renders the BOX column for an app.
func (i iconSet) box(a App) (string, lipgloss.Style) {
	if a.HostOnly {
		return i.dash(), styDesc
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
func (i iconSet) dash() string      { return "─" }
