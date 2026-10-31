package main

import (
	"strings"
	"testing"
)

// The rendered notes must follow the markdown, not its length: v1.2.0 and
// v1.3.0 are the same size, and a rebuild from one to the other used to keep
// showing the first.
func TestReleaseNotesFollowContent(t *testing.T) {
	p := newInfoPanel(appsDir, newIconSet(false))
	a := App{Name: "pi", HasWizard: true, HasImage: true, Record: &InstallRecord{Release: "v1.2.0"}}
	first := p.releaseNotes(a, &appUpdate{State: updCurrent, Installed: "v1.2.0"}, 60)
	if !strings.Contains(first, "v1.2.0") {
		t.Fatalf("first render lacks v1.2.0:\n%s", first)
	}

	a.Record = &InstallRecord{Release: "v1.3.0"}
	second := p.releaseNotes(a, &appUpdate{State: updCurrent, Installed: "v1.3.0"}, 60)
	if !strings.Contains(second, "v1.3.0") || strings.Contains(second, "v1.2.0") {
		t.Fatalf("second render is stale:\n%s", second)
	}
	if n := len(p.notesCache); n != 1 {
		t.Errorf("notesCache has %d entries, want 1 (replaced, not accumulated)", n)
	}
}
