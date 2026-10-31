package main

import (
	"fmt"
	"hash/fnv"
	"strings"
	"time"
)

// renderedNotes is one app's rendered notes at one width, with a hash of the
// markdown it was rendered from.
type renderedNotes struct {
	sum uint64
	out string
}

// releaseNotes renders the info panel's notes mode: every release between the
// installed one and the newest, newest first, so skipping three releases shows
// all three; or, when there is nothing newer, the installed release's own
// notes.
//
// The markdown is rebuilt on every call (it is cheap); only the glamour render
// is cached, and only while the markdown is unchanged. The check is on the
// content itself: a rebuild between two equal-length tags, or a refresh that
// swaps notes for others of the same size, changes it without changing its
// length. One entry per app and width, replaced rather than added to, so
// repeated refreshes do not accumulate renderings.
func (p *infoPanel) releaseNotes(a App, upd *appUpdate, width int) string {
	src := notesMarkdown(a, upd)
	h := fnv.New64a()
	h.Write([]byte(src))
	sum := h.Sum64()

	key := fmt.Sprintf("%s@%d", a.Name, width)
	if c, ok := p.notesCache[key]; ok && c.sum == sum {
		return c.out
	}
	out, err := renderMarkdown(src, width)
	if err != nil {
		out = styWarn.Render("could not render release notes: " + err.Error())
	}
	p.notesCache[key] = renderedNotes{sum: sum, out: out}
	return out
}

func notesMarkdown(a App, upd *appUpdate) string {
	var b strings.Builder
	switch {
	case a.HostOnly || !a.HasWizard:
		b.WriteString("# " + a.Name + "\n\nThis app has no release picker, so there is no release to track.\n")
		return b.String()
	case a.Record == nil || a.Record.Release == "":
		b.WriteString("# " + a.Name + "\n\n")
		if !a.HasImage {
			b.WriteString("Not installed.\n")
		} else {
			b.WriteString("The installed version is unknown: this image was built before linux-tools " +
				"recorded installed releases. It is recorded on the next `tools setup " + a.Name + "`.\n")
		}
		return b.String()
	case upd == nil:
		b.WriteString("# " + a.Name + " " + a.Record.Release + "\n\nNot checked for updates.\n")
		return b.String()
	}

	built := ""
	if !a.Record.BuiltAt.IsZero() {
		built = " · built " + ago(a.Record.BuiltAt)
	}
	switch upd.State {
	case updChecking:
		b.WriteString("# " + a.Name + " " + upd.Installed + "\n\nChecking for a newer release…\n")
	case updBranch:
		fmt.Fprintf(&b, "# %s %s\n\nInstalled from `%s`, which moves with upstream, so there is no "+
			"version to compare%s. Rebuild to pick up the latest.\n", a.Name, upd.Installed, upd.Installed, built)
	case updUnknown:
		fmt.Fprintf(&b, "# %s %s\n\n", a.Name, upd.Installed)
		if upd.Err != "" {
			b.WriteString("Could not check for updates: " + upd.Err + "\n")
		} else {
			b.WriteString("The installed release is not one the picker lists, so it cannot be compared.\n")
		}
	case updAvailable:
		n := len(upd.Newer)
		fmt.Fprintf(&b, "# %s %s → %s\n\n%d newer release%s%s. Install with `tools setup %s`.\n",
			a.Name, upd.Installed, upd.Latest, n, plural(n), built, a.Name)
		for _, r := range upd.Newer {
			writeRelease(&b, r)
		}
	case updCurrent:
		fmt.Fprintf(&b, "# %s %s\n\nUp to date%s.\n", a.Name, upd.Installed, built)
		if upd.Current != nil {
			writeRelease(&b, *upd.Current)
		}
	}
	return b.String()
}

func writeRelease(b *strings.Builder, r releaseItem) {
	head := r.Name
	if r.NotesTitle != "" {
		head += " — " + r.NotesTitle
	}
	b.WriteString("\n---\n\n## " + head + "\n\n")
	if r.Desc != "" {
		b.WriteString("*" + r.Desc + "*\n\n")
	}
	if strings.TrimSpace(r.Notes) == "" {
		b.WriteString("No release notes.\n")
		return
	}
	b.WriteString(r.Notes + "\n")
}

func plural(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}

// ago is a coarse "3 days ago".
func ago(t time.Time) string {
	d := time.Since(t)
	switch {
	case d < time.Hour:
		return "just now"
	case d < 48*time.Hour:
		return fmt.Sprintf("%dh ago", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd ago", int(d.Hours()/24))
	}
}
