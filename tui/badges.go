package main

import (
	"regexp"
	"strings"

	"charm.land/lipgloss/v2"
)

// Compatibility badges.
//
// Every apps/<name>/README.md opens with a shields.io badge row saying which
// distros the app has been run on. On GitHub those are images; in this panel
// they are drawn as two-tone pills, so the same fact reaches both audiences
// from one source — the README — with no per-app metadata file to drift.
//
// The row is raw HTML in the README on purpose (see CLAUDE.md): glamour
// expands a markdown image into three lines of "Image: <alt> -> <full URL>",
// which would bury the app's description under shields.io URLs. Raw HTML it
// skips entirely, which is why we lift the badges out ourselves.

// badgePlaceholder stands in for the badge row while glamour renders the rest
// of the document. It survives rendering as an ordinary one-word paragraph,
// which gives us glamour's own left margin to align the pills against.
const badgePlaceholder = "%%LT-BADGES%%"

// badge is one distro's verdict: "Ubuntu" / "tested".
type badge struct {
	label string
	value string
	ok    bool
}

var (
	// The badge row: the first HTML paragraph holding shields.io images.
	badgeBlockRe = regexp.MustCompile(`(?s)<p>\s*(?:<img[^>]*>\s*)+</p>`)
	badgeImgRe   = regexp.MustCompile(`<img\s+[^>]*>`)
	badgeAltRe   = regexp.MustCompile(`alt="([^"]*)"`)
	badgeSrcRe   = regexp.MustCompile(`src="([^"]*)"`)
)

// extractBadges pulls the badge row out of a README, returning the markdown
// with the row swapped for badgePlaceholder and the badges it found.
//
// A README with no badge row comes back untouched and with no badges, so apps
// that predate the convention still render normally.
func extractBadges(md string) (string, []badge) {
	loc := badgeBlockRe.FindStringIndex(md)
	if loc == nil {
		return md, nil
	}
	block := md[loc[0]:loc[1]]
	if !strings.Contains(block, "img.shields.io") {
		return md, nil
	}

	var badges []badge
	for _, tag := range badgeImgRe.FindAllString(block, -1) {
		alt := badgeAltRe.FindStringSubmatch(tag)
		if alt == nil {
			continue
		}
		label, value, found := strings.Cut(alt[1], ":")
		if !found {
			continue
		}
		// The colour in the shields URL is the authoritative verdict; the alt
		// text only has to agree with it for screen readers and for GitHub.
		src := ""
		if m := badgeSrcRe.FindStringSubmatch(tag); m != nil {
			src = m[1]
		}
		badges = append(badges, badge{
			label: strings.TrimSpace(label),
			value: strings.TrimSpace(value),
			ok:    strings.Contains(src, "-brightgreen") || strings.Contains(src, "-green"),
		})
	}
	if len(badges) == 0 {
		return md, nil
	}
	return md[:loc[0]] + badgePlaceholder + md[loc[1]:], badges
}

var (
	// Two-tone pills, the same shape shields.io draws: a label half carrying
	// the distro and a verdict half coloured by the answer. The label's
	// foreground is set per badge, from the distro's brand colour.
	styBadgeLabel = lipgloss.NewStyle().Background(colSelBg).Padding(0, 1)
	styBadgeOK    = lipgloss.NewStyle().Bold(true).
			Foreground(lipgloss.Color("#1d2021")).Background(colOK).Padding(0, 1)
	styBadgeNo = lipgloss.NewStyle().
			Foreground(colDim).Background(colBorder).Padding(0, 1)
)

// renderBadges lays the pills out in rows no wider than width, wrapping rather
// than spilling past the panel edge and corrupting the column layout.
//
// The label half shows the distro's Nerd Font glyph, matching the icon-only
// badge GitHub shows; without a patched font (--ascii) icons.distro falls back
// to the distro's name, so the row never degrades to unlabelled pills.
func renderBadges(badges []badge, width int, icons iconSet) []string {
	if len(badges) == 0 {
		return nil
	}
	if width < 10 {
		width = 10
	}

	var (
		lines []string
		cur   string
		curW  int
	)
	for _, b := range badges {
		verdict := styBadgeNo
		if b.ok {
			verdict = styBadgeOK
		}
		label := styBadgeLabel.Foreground(icons.distroColour(b.label))
		pill := label.Render(icons.distro(b.label)) + verdict.Render(b.value)
		pw := lipgloss.Width(pill)

		switch {
		case cur == "":
			cur, curW = pill, pw
		case curW+1+pw <= width:
			cur, curW = cur+" "+pill, curW+1+pw
		default:
			lines = append(lines, cur)
			cur, curW = pill, pw
		}
	}
	if cur != "" {
		lines = append(lines, cur)
	}
	return lines
}

// injectBadges swaps the rendered placeholder line for the pill rows, reusing
// that line's left margin so the badges align with glamour's body text.
func injectBadges(rendered string, badges []badge, width int, icons iconSet) string {
	lines := strings.Split(rendered, "\n")
	for i, l := range lines {
		if !strings.Contains(l, badgePlaceholder) {
			continue
		}
		indent := l[:len(l)-len(strings.TrimLeft(l, " "))]
		pills := renderBadges(badges, width-len(indent), icons)
		out := make([]string, 0, len(lines)+len(pills))
		out = append(out, lines[:i]...)
		for _, p := range pills {
			out = append(out, indent+p)
		}
		return strings.Join(append(out, lines[i+1:]...), "\n")
	}
	return rendered
}
