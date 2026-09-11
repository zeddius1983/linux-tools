package main

import (
	"charm.land/lipgloss/v2"
	"strings"
	"testing"
)

const shields = "https://img.shields.io/badge"

func badgeReadme(cachy string) string {
	return "# nvtop\n\n<p>\n" +
		`  <img alt="Ubuntu: tested" src="` + shields + `/Ubuntu-tested-brightgreen?logo=ubuntu&logoColor=white">` + "\n" +
		`  <img alt="Linux Mint: tested" src="` + shields + `/Linux_Mint-tested-brightgreen?logo=linuxmint&logoColor=white">` + "\n" +
		`  <img alt="CachyOS: ` + cachy + `" src="` + shields + `/CachyOS-` + cachy + `-lightgrey?logo=archlinux&logoColor=white">` + "\n" +
		"</p>\n\nSome description.\n"
}

func TestExtractBadges(t *testing.T) {
	src, badges := extractBadges(badgeReadme("untested"))

	if len(badges) != 3 {
		t.Fatalf("got %d badges, want 3: %+v", len(badges), badges)
	}
	want := []badge{
		{label: "Ubuntu", value: "tested", ok: true},
		{label: "Linux Mint", value: "tested", ok: true},
		{label: "CachyOS", value: "untested", ok: false},
	}
	for i, w := range want {
		if badges[i] != w {
			t.Errorf("badge %d = %+v, want %+v", i, badges[i], w)
		}
	}

	// The HTML must be gone, replaced by a placeholder glamour can render, or
	// the row would be dropped silently and the pills would have nowhere to go.
	if strings.Contains(src, "<img") || strings.Contains(src, "shields.io") {
		t.Errorf("badge HTML survived extraction:\n%s", src)
	}
	if !strings.Contains(src, badgePlaceholder) {
		t.Errorf("placeholder missing from:\n%s", src)
	}
	if !strings.Contains(src, "# nvtop") || !strings.Contains(src, "Some description.") {
		t.Errorf("extraction ate surrounding content:\n%s", src)
	}
}

// The verdict comes from the shields colour, not the alt text, so a README
// whose two halves disagree still renders the colour a reader sees on GitHub.
func TestExtractBadgesVerdictFollowsColour(t *testing.T) {
	_, badges := extractBadges(badgeReadme("tested"))
	if len(badges) != 3 {
		t.Fatalf("got %d badges, want 3", len(badges))
	}
	if badges[2].ok {
		t.Errorf("CachyOS badge on a -lightgrey URL reported ok; colour must win over alt text")
	}
}

// Apps that predate the convention must render exactly as before.
func TestExtractBadgesNoBadgeRow(t *testing.T) {
	plain := "# plain\n\nJust a README.\n"
	src, badges := extractBadges(plain)
	if badges != nil {
		t.Errorf("found badges in a plain README: %+v", badges)
	}
	if src != plain {
		t.Errorf("plain README was modified:\n%q", src)
	}
}

// An unrelated HTML paragraph (a <details> block, a centred image) must not be
// mistaken for the badge row.
func TestExtractBadgesIgnoresNonShieldsHTML(t *testing.T) {
	md := "# app\n\n<p>\n  <img alt=\"diagram\" src=\"docs/diagram.png\">\n</p>\n"
	src, badges := extractBadges(md)
	if badges != nil {
		t.Errorf("non-shields HTML parsed as badges: %+v", badges)
	}
	if src != md {
		t.Errorf("non-shields HTML was rewritten:\n%q", src)
	}
}

func TestInjectBadgesKeepsIndentAndOrder(t *testing.T) {
	badges := []badge{
		{label: "Ubuntu", value: "tested", ok: true},
		{label: "CachyOS", value: "untested", ok: false},
	}
	rendered := "  title\n\n  " + badgePlaceholder + "\n\n  body text"
	out := injectBadges(rendered, badges, 80, newIconSet(false))

	if strings.Contains(out, badgePlaceholder) {
		t.Errorf("placeholder left in output:\n%s", out)
	}
	lines := strings.Split(out, "\n")
	if len(lines) != 5 {
		t.Fatalf("got %d lines, want 5 (one row at width 80):\n%s", len(lines), out)
	}
	if !strings.HasPrefix(lines[2], "  ") {
		t.Errorf("badge row lost glamour's left margin: %q", lines[2])
	}
	if !strings.Contains(lines[2], "Ubuntu") || !strings.Contains(lines[2], "CachyOS") {
		t.Errorf("badge row missing labels: %q", lines[2])
	}
	if lines[0] != "  title" || lines[4] != "  body text" {
		t.Errorf("surrounding lines disturbed:\n%s", out)
	}
}

// A narrow panel must wrap the row rather than spill past the panel edge and
// corrupt the column layout.
func TestRenderBadgesWrapsWhenNarrow(t *testing.T) {
	badges := []badge{
		{label: "Ubuntu", value: "tested", ok: true},
		{label: "Linux Mint", value: "tested", ok: true},
		{label: "CachyOS", value: "untested", ok: false},
	}
	if got := renderBadges(badges, 200, newIconSet(false)); len(got) != 1 {
		t.Errorf("width 200: got %d rows, want 1", len(got))
	}
	narrow := renderBadges(badges, 20, newIconSet(false))
	if len(narrow) < 2 {
		t.Errorf("width 20: got %d rows, want the row wrapped", len(narrow))
	}
	for i, l := range narrow {
		if w := lipgloss.Width(l); w > 20 {
			t.Errorf("row %d is %d cells wide, want <= 20", i, w)
		}
	}
}

func TestRenderBadgesEmpty(t *testing.T) {
	if got := renderBadges(nil, 80, newIconSet(false)); got != nil {
		t.Errorf("got %v, want nil", got)
	}
}

// With a patched font the label half is the distro's glyph; with --ascii it
// must fall back to the name, never to an empty pill.
func TestRenderBadgesGlyphAndAsciiFallback(t *testing.T) {
	badges := []badge{{label: "Ubuntu", value: "tested", ok: true}}

	nerd := renderBadges(badges, 200, newIconSet(true))[0]
	if strings.Contains(nerd, "Ubuntu") {
		t.Errorf("nerd row still spells the distro out: %q", nerd)
	}
	if !strings.Contains(nerd, "") {
		t.Errorf("nerd row missing the Ubuntu glyph: %q", nerd)
	}

	ascii := renderBadges(badges, 200, newIconSet(false))[0]
	if !strings.Contains(ascii, "Ubuntu") {
		t.Errorf("--ascii row lost the distro name: %q", ascii)
	}
	if strings.Contains(ascii, "") {
		t.Errorf("--ascii row emitted a Nerd Font glyph: %q", ascii)
	}
}

// CachyOS has no glyph of its own and borrows Arch's, the same fallback
// statusline.sh makes; an unmapped distro keeps its name rather than going
// blank.
func TestDistroGlyphFallbacks(t *testing.T) {
	nerd := newIconSet(true)
	if got := nerd.distro("CachyOS"); got != "" {
		t.Errorf("CachyOS glyph = %q, want the Arch glyph", got)
	}
	if got := nerd.distro("Slackware"); got != "Slackware" {
		t.Errorf("unmapped distro = %q, want its name", got)
	}
}
