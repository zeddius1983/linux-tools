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

// The panel opens on release notes for an app with a newer release and on
// the README otherwise; n flips that for the selected app only.
func TestInfoPanelDefaultsToNotesWhenUpdateAvailable(t *testing.T) {
	p := newInfoPanel(appsDir, newIconSet(false))
	pi := App{Name: "pi", HasWizard: true, HasImage: true, Record: &InstallRecord{Release: "v1.2.0"}}
	avail := &appUpdate{State: updAvailable, Installed: "v1.2.0", Latest: "v1.4.0"}
	current := &appUpdate{State: updCurrent, Installed: "v1.4.0"}
	other := App{Name: "dev-toolbox"}

	if !p.showsNotes(pi, avail) {
		t.Error("an app with an update should open on its release notes")
	}
	if p.showsNotes(pi, current) || p.showsNotes(pi, nil) || p.showsNotes(other, nil) {
		t.Error("an app without an update should open on its README")
	}

	p.view(pi, avail, 60, 10)
	p.toggleNotes(pi)
	if p.showsNotes(pi, avail) {
		t.Error("n should flip an updatable app to its README")
	}
	if !p.showsNotes(other, avail) {
		t.Error("the flip belongs to the app it was made on")
	}

	// Moving away and back drops the flip.
	p.view(other, nil, 60, 10)
	p.view(pi, avail, 60, 10)
	if !p.showsNotes(pi, avail) {
		t.Error("returning to the app should show its default again")
	}

	// n on an app without an update shows its notes.
	p.view(other, nil, 60, 10)
	p.toggleNotes(other)
	if !p.showsNotes(other, nil) {
		t.Error("n should flip an app without an update to its notes")
	}
}
