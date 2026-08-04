package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// testApp builds an App pointing at a real app directory in the repo, so the
// session tests run against the shipped wizard pages rather than fixtures.
func testApp(t *testing.T, name string) App {
	t.Helper()
	a := App{Name: name, WizardDir: filepath.Join(appsDir, name, "wizard"), HasWizard: true}
	if _, err := os.Stat(a.WizardDir); err != nil {
		t.Fatalf("%s has no wizard dir: %v", name, err)
	}
	return a
}

// A page declaring "setup,create" must open for those actions and no others —
// the same gate _wizard_run_page applies.
func TestSessionFiltersByAction(t *testing.T) {
	a := testApp(t, "lmstudio")
	for _, action := range []string{"setup", "create"} {
		w, _ := newWizardSession(a, action, t.TempDir())
		if w == nil || len(w.pages) != 1 {
			t.Fatalf("%s: expected one page, got %v", action, w)
		}
	}
	if w, _ := newWizardSession(a, "build", t.TempDir()); w != nil {
		t.Errorf("build: expected no session, got %d pages", len(w.pages))
	}
}

// An app with no wizard at all yields no session, which is what makes the
// caller fall through to running the action directly.
func TestSessionNilWithoutWizard(t *testing.T) {
	if w, _ := newWizardSession(App{Name: "nope"}, "setup", t.TempDir()); w != nil {
		t.Error("expected nil session for an app with no wizard")
	}
}

// Checkboxes start from what is on disk: a tool whose detect path exists is
// pre-ticked, one whose path does not is not.
func TestSessionPrefillsFromDisk(t *testing.T) {
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}

	a := testApp(t, "claude-code")
	w, _ := newWizardSession(a, "setup", home)
	if w == nil {
		t.Fatal("no session")
	}
	p := w.page()
	if p.checked[0] {
		t.Error("statusline ticked before its detect path exists")
	}

	if err := os.WriteFile(filepath.Join(home, ".claude", "statusline.sh"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	w, _ = newWizardSession(a, "setup", home)
	if !w.page().checked[0] {
		t.Error("statusline not ticked though its detect path exists")
	}
}

// The runtime variant reaches bash as the value, not the label: cmd_create looks
// for create_flags.nvidia, and "NVIDIA (CUDA)" would find nothing.
func TestSessionRuntimeStateUsesValue(t *testing.T) {
	w, _ := newWizardSession(testApp(t, "lmstudio"), "setup", t.TempDir())
	w.page().radio = 1

	st := w.state()
	if st.Variant != "nvidia" {
		t.Errorf("Variant = %q, want %q", st.Variant, "nvidia")
	}
	if got := st.Pages["00-runtime"]; len(got) != 1 || got[0] != "NVIDIA (CUDA)" {
		t.Errorf("page selection = %v, want the label", got)
	}
}

// Build args must render as the two tokens cmd_build reads with mapfile.
func TestSessionBuildArgTokens(t *testing.T) {
	w, _ := newWizardSession(testApp(t, "fastflowlm"), "setup", t.TempDir())
	p := w.page()
	p.loading = false
	p.items = []Item{{Name: "v0.9.12"}, {Name: "v0.9.11"}}
	p.radio = 0

	st := w.state()
	if len(st.BuildArgs) != 2 || st.BuildArgs[0] != "--build-arg" || st.BuildArgs[1] != "FLM_REF=v0.9.12" {
		t.Fatalf("BuildArgs = %v", st.BuildArgs)
	}
	if !strings.Contains(st.Render(), `BUILD_ARGS="--build-arg FLM_REF=v0.9.12"`) {
		t.Errorf("rendered state missing build args:\n%s", st.Render())
	}
}

// An items-cmd that produced nothing leaves the page unanswered, so the build
// keeps its Dockerfile default instead of being handed an empty --build-arg.
func TestSessionBuildArgFailureLeavesDefault(t *testing.T) {
	w, _ := newWizardSession(testApp(t, "fastflowlm"), "setup", t.TempDir())
	p := w.page()
	p.loading = false
	p.loadErr = os.ErrNotExist

	st := w.state()
	if len(st.BuildArgs) != 0 {
		t.Errorf("BuildArgs = %v, want none", st.BuildArgs)
	}
	if _, ok := st.Pages["00-release"]; ok {
		t.Error("unanswered page written to the state file")
	}
	if w.ready() != true {
		t.Error("a failed page must not block the wizard")
	}
}

// Deselecting everything is an answer, not an absence: the page must still be
// written so the apply handler removes what is installed.
func TestSessionDeselectAllStillWritesPage(t *testing.T) {
	w, _ := newWizardSession(testApp(t, "dev-toolbox"), "setup", t.TempDir())
	p := w.page()
	for i := range p.checked {
		p.checked[i] = false
	}

	st := w.state()
	sel, ok := st.Pages["00-tools"]
	if !ok {
		t.Fatal("page not written when nothing is selected")
	}
	if len(sel) != 0 {
		t.Errorf("selection = %v, want empty", sel)
	}
	if !strings.Contains(st.Render(), `PAGE_00_tools=""`) {
		t.Errorf("rendered state missing the empty page:\n%s", st.Render())
	}
}

// The confirm screen's diff mirrors tui_confirm_wizards: ticked-but-absent is an
// install, unticked-but-present is a removal, and unchanged rows say nothing.
func TestSessionDiff(t *testing.T) {
	home := t.TempDir()
	bin := filepath.Join(home, ".local", "share", "dev-toolbox", "uv", "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "uv"), []byte("x"), 0o755); err != nil {
		t.Fatal(err)
	}

	w, _ := newWizardSession(testApp(t, "dev-toolbox"), "setup", home)
	p := w.page()
	for i, it := range p.items {
		switch it.Name {
		case "uv":
			p.checked[i] = false // installed, now unticked → remove
		case "node":
			p.checked[i] = true // not installed, ticked → install
		default:
			p.checked[i] = false
		}
	}

	install, remove := w.diff()
	if len(install) != 1 || !strings.HasPrefix(install[0], "node") {
		t.Errorf("install = %v, want just node", install)
	}
	if len(remove) != 1 || !strings.HasPrefix(remove[0], "uv") {
		t.Errorf("remove = %v, want just uv", remove)
	}
}

// Key handling: toggling, all/none, advancing to the review screen and backing
// out of the wizard entirely.
func TestWizardKeys(t *testing.T) {
	m := newModel([]App{}, appsDir, "tools", true)
	m.wiz, _ = newWizardSession(testApp(t, "dev-toolbox"), "setup", t.TempDir())
	p := m.wiz.page()

	m.wizardKey("n")
	for i := range p.checked {
		if p.checked[i] {
			t.Fatal("n did not clear every checkbox")
		}
	}
	m.wizardKey("space")
	if !p.checked[0] {
		t.Error("space did not tick the row under the cursor")
	}
	m.wizardKey("j")
	m.wizardKey("space")
	if !p.checked[1] {
		t.Error("cursor did not move with j")
	}
	m.wizardKey("a")
	for i := range p.checked {
		if !p.checked[i] {
			t.Fatal("a did not tick every checkbox")
		}
	}

	// One page only, so Enter goes straight to the review screen.
	m.wizardKey("enter")
	if m.wiz.stage != stageConfirm {
		t.Fatal("enter did not reach the confirm stage")
	}
	m.wizardKey("esc")
	if m.wiz.stage != stagePages {
		t.Fatal("esc did not return to the pages")
	}
	// Esc on the first page leaves the wizard rather than going nowhere.
	m.wizardKey("esc")
	if m.wiz != nil {
		t.Error("esc on the first page did not cancel the wizard")
	}
}

// Enter commits the highlighted row on a single-choice page: requiring Space
// first is a trap when the highlight already reads as the selection.
func TestWizardEnterCommitsRadio(t *testing.T) {
	m := newModel([]App{}, appsDir, "tools", true)
	m.wiz, _ = newWizardSession(testApp(t, "lmstudio"), "setup", t.TempDir())

	m.wizardKey("j")
	m.wizardKey("enter")
	if m.wiz.stage != stageConfirm {
		t.Fatal("enter did not reach the confirm stage")
	}
	if got := m.wiz.state().Variant; got != "nvidia" {
		t.Errorf("Variant = %q, want the row under the cursor", got)
	}
}

// A page still resolving its items holds Enter, so a run cannot start with a
// half-collected answer.
func TestWizardWaitsForLoadingPage(t *testing.T) {
	m := newModel([]App{}, appsDir, "tools", true)
	m.wiz, _ = newWizardSession(testApp(t, "fastflowlm"), "setup", t.TempDir())

	m.wizardKey("enter")
	if m.wiz.stage == stageConfirm {
		t.Error("enter advanced past a page that is still loading")
	}
	m.wizardUpdate(wizItemsMsg{page: 0, values: []string{"v1", "v0"}})
	if m.wiz.page().loading {
		t.Fatal("page still loading after its items arrived")
	}
	m.wizardKey("enter")
	if m.wiz.stage != stageConfirm {
		t.Error("enter did not advance once the items had arrived")
	}
}
