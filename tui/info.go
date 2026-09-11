package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"charm.land/glamour/v2"
	"charm.land/lipgloss/v2"
)

// infoPanel renders the right-hand pane: app metadata followed by the app's
// README.md as rendered markdown.
//
// Rendering markdown is not free, so results are cached per (app, width).
type infoPanel struct {
	appsDir string
	cache   map[string]string
	top     int // scroll offset in rendered lines
}

func newInfoPanel(appsDir string) *infoPanel {
	return &infoPanel{appsDir: appsDir, cache: map[string]string{}}
}

// readme returns the rendered README for an app, or a placeholder.
func (p *infoPanel) readme(app string, width int) string {
	key := fmt.Sprintf("%s@%d", app, width)
	if v, ok := p.cache[key]; ok {
		return v
	}

	raw, err := os.ReadFile(filepath.Join(p.appsDir, app, "README.md"))
	if err != nil {
		out := styDesc.Render("No README.md for this app.")
		p.cache[key] = out
		return out
	}

	// The compatibility badge row is raw HTML, which glamour drops on the
	// floor. Lift it out first and paint it back in after rendering.
	src, badges := extractBadges(string(raw))

	md, err := renderMarkdown(src, width)
	if err != nil {
		out := styWarn.Render("could not render README: " + err.Error())
		p.cache[key] = out
		return out
	}
	md = injectBadges(md, badges, width)
	p.cache[key] = md
	return md
}

// renderMarkdown renders markdown to fit a pane of the given width. Shared with
// the wizard's release-notes panel, which is the same problem in a narrower
// column.
func renderMarkdown(src string, width int) (string, error) {
	// Word wrap has to leave room for glamour's own left margin, or long lines
	// spill past the panel and corrupt the column layout.
	w := width - 2
	if w < 20 {
		w = 20
	}
	r, err := glamour.NewTermRenderer(
		glamour.WithStandardStyle("dark"),
		glamour.WithWordWrap(w),
	)
	if err != nil {
		return "", err
	}
	out, err := r.Render(src)
	if err != nil {
		return "", err
	}
	return strings.TrimRight(out, "\n"), nil
}

// view renders the panel for one app: the rendered README, nothing else.
// Image/box state lives in the table columns, so repeating it here would only
// steal rows from the README.
func (p *infoPanel) view(a App, width, height int) string {
	body := strings.Split(p.readme(a.Name, width), "\n")

	if p.top > len(body)-height {
		p.top = len(body) - height
	}
	if p.top < 0 {
		p.top = 0
	}
	end := p.top + height
	if end > len(body) {
		end = len(body)
	}

	lines := append([]string{}, body[p.top:end]...)
	// Pad so the panel keeps a constant height and the footer does not jump.
	for len(lines) < height {
		lines = append(lines, "")
	}
	for i, l := range lines {
		lines[i] = lipgloss.NewStyle().MaxWidth(width).Render(l)
	}
	return strings.Join(lines, "\n")
}

// scrollInfo reports whether the README overflows the panel, for a hint.
func (p *infoPanel) canScroll(a App, width, height int) bool {
	return len(strings.Split(p.readme(a.Name, width), "\n")) > height
}

// scroll moves the README view, clamped by the caller's next render.
func (p *infoPanel) scroll(delta int) {
	p.top += delta
	if p.top < 0 {
		p.top = 0
	}
}

func (p *infoPanel) resetScroll() { p.top = 0 }
