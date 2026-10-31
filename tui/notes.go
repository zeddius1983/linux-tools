package main

import (
	"fmt"
	"strings"
	"time"
)

// releaseNotes renders the info panel's notes mode: every release between the
// installed one and the newest, newest first, so skipping three releases shows
// all three; or, when there is nothing newer, the installed release's own
// notes.
func (p *infoPanel) releaseNotes(a App, upd *appUpdate, width int) string {
	src := notesMarkdown(a, upd)
	key := fmt.Sprintf("notes:%s@%d:%d", a.Name, width, len(src))
	if v, ok := p.cache[key]; ok {
		return v
	}
	out, err := renderMarkdown(src, width)
	if err != nil {
		out = styWarn.Render("could not render release notes: " + err.Error())
	}
	p.cache[key] = out
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
