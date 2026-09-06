package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

// keyPress builds the message the dashboard's key handler expects, so tests can
// exercise the real binding rather than a stringly-typed shortcut into it.
func keyPress(name string) tea.KeyPressMsg {
	switch name {
	case "enter":
		return tea.KeyPressMsg{Code: tea.KeyEnter}
	default:
		return tea.KeyPressMsg{Code: rune(name[0]), Text: name}
	}
}

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

// A .runtime page with an 'arg|NAME' line feeds the build as well as the
// create: the variant's value must show up as a --build-arg, not its label.
func TestSessionRuntimeArgEmitsBuildArg(t *testing.T) {
	w, _ := newWizardSession(testApp(t, "comfyui"), "setup", t.TempDir())
	w.page().radio = 1 // NVIDIA (CUDA)

	st := w.state()
	if st.Variant != "nvidia" {
		t.Errorf("Variant = %q, want nvidia", st.Variant)
	}
	if len(st.BuildArgs) < 2 || st.BuildArgs[0] != "--build-arg" || st.BuildArgs[1] != "COMFY_GPU=nvidia" {
		t.Fatalf("BuildArgs = %v, want the COMFY_GPU pair first", st.BuildArgs)
	}
}

// A .runtime page without an arg line must not start emitting build args.
func TestSessionRuntimeWithoutArgEmitsNoBuildArg(t *testing.T) {
	w, _ := newWizardSession(testApp(t, "lmstudio"), "setup", t.TempDir())
	w.page().radio = 1

	if st := w.state(); len(st.BuildArgs) != 0 {
		t.Errorf("BuildArgs = %v, want none", st.BuildArgs)
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

// The wheel scrolls whichever pane the pointer is over: the README on the
// right, the app list on the left.
func TestWheelScrollsPaneUnderPointer(t *testing.T) {
	apps, err := LoadApps(appsDir)
	if err != nil {
		t.Fatal(err)
	}
	m := newModel(apps, appsDir, "tools", true)
	m.w, m.h = 120, 30
	// A README long enough to have somewhere to scroll to.
	m.selectApp("dev-toolbox")

	row := m.rowIdx
	panelX := m.tableWidth() + dividerWidth
	m.onWheel(tea.MouseWheelMsg{X: panelX + 2, Button: tea.MouseWheelDown})
	if m.info.top == 0 {
		t.Error("wheel over the panel did not scroll the README")
	}
	if m.rowIdx != row {
		t.Errorf("wheel over the panel moved the selection from %d to %d", row, m.rowIdx)
	}

	before := m.rowIdx
	m.onWheel(tea.MouseWheelMsg{X: 2, Button: tea.MouseWheelDown})
	if m.rowIdx == before {
		t.Error("wheel over the table did not move the selection")
	}
	if m.info.top != 0 {
		t.Error("moving the selection did not reset the README scroll")
	}
}

// Terminals report one physical notch as a burst of wheel events. Over the app
// list that moved the selection several apps at a time, so a burst has to
// collapse into a single row.
func TestWheelBurstIsOneRow(t *testing.T) {
	apps, err := LoadApps(appsDir)
	if err != nil {
		t.Fatal(err)
	}
	m := newModel(apps, appsDir, "tools", true)
	m.w, m.h = 120, 30

	down := tea.MouseWheelMsg{X: 2, Button: tea.MouseWheelDown}
	for i := 0; i < 3; i++ {
		m.onWheel(down)
	}
	if m.rowIdx != 1 {
		t.Errorf("a 3-event burst moved %d rows, want 1", m.rowIdx)
	}

	// A notch far enough apart in time is a separate notch.
	m.lastWheelAt = m.lastWheelAt.Add(-wheelNotch * 2)
	m.onWheel(down)
	if m.rowIdx != 2 {
		t.Errorf("the next notch moved to row %d, want 2", m.rowIdx)
	}

	// Reversing direction is deliberate, never part of a burst.
	m.onWheel(tea.MouseWheelMsg{X: 2, Button: tea.MouseWheelUp})
	if m.rowIdx != 1 {
		t.Errorf("reversing direction moved to row %d, want 1", m.rowIdx)
	}
}

// items-cmd takes seconds. Cancelling one wizard and opening another before it
// returns must not put the first app's releases into the second app's page.
func TestStaleItemsAreIgnored(t *testing.T) {
	m := newModel([]App{}, appsDir, "tools", true)

	m.wiz, _ = newWizardSession(testApp(t, "fastflowlm"), "setup", t.TempDir())
	stale := m.wiz.id
	m.wizardKey("q") // cancel while its items-cmd is still in flight

	m.wiz, _ = newWizardSession(testApp(t, "llama-cpp-rocm"), "setup", t.TempDir())
	m.wizardUpdate(wizItemsMsg{session: stale, page: 0, values: []string{"v0.9.12"}})

	if p := m.wiz.page(); len(p.items) != 0 || !p.loading {
		t.Errorf("the cancelled wizard's items landed in the new one: %v", p.items)
	}

	// Its own result is still accepted.
	m.wizardUpdate(wizItemsMsg{session: m.wiz.id, page: 0, values: []string{"b1234"}})
	if got := m.wiz.page().items; len(got) != 1 || got[0].Name != "b1234" {
		t.Errorf("items = %v, want the session's own result", got)
	}
}

// A wizard page must never draw more rows than the screen has: shell-toolbox
// ships 18 items, which would push the footer off a 24-line terminal.
func TestWizardPageFitsTheScreen(t *testing.T) {
	m := newModel([]App{}, appsDir, "tools", true)
	m.w, m.h = 100, 24
	m.wiz, _ = newWizardSession(testApp(t, "shell-toolbox"), "setup", t.TempDir())
	if len(m.wiz.page().items) < 18 {
		t.Fatalf("expected the long page, got %d items", len(m.wiz.page().items))
	}

	for _, cursor := range []int{0, 9, 17} {
		m.wiz.cursor = cursor
		lines := strings.Count(m.wizardView(), "\n") + 1
		if lines > m.h {
			t.Errorf("cursor %d: %d lines, want at most %d", cursor, lines, m.h)
		}
		// The cursor has to be one of the drawn rows, or it is invisible.
		top, end := m.wiz.window(m.wizardRows())
		if cursor < top || cursor >= end {
			t.Errorf("cursor %d outside the drawn window %d-%d", cursor, top, end)
		}
	}
}

// On a terminal too narrow for both panes the README is dropped and the table
// takes the full width, rather than both being squeezed.
func TestPanelHiddenWhenNarrow(t *testing.T) {
	apps, err := LoadApps(appsDir)
	if err != nil {
		t.Fatal(err)
	}
	m := newModel(apps, appsDir, "tools", true)
	m.h = 24

	m.w = minTableWidth + dividerWidth + minPanelWidth
	if !m.showInfo() {
		t.Errorf("panel hidden at %d, the width it just fits in", m.w)
	}
	if !strings.Contains(m.View().Content, "│") {
		t.Error("no divider drawn while the panel is shown")
	}

	m.w--
	if m.showInfo() {
		t.Errorf("panel still shown at %d", m.w)
	}
	if m.tableWidth() != m.w {
		t.Errorf("table width = %d, want the full %d", m.tableWidth(), m.w)
	}
	view := m.View().Content
	if strings.Contains(view, "│") {
		t.Error("divider drawn with no panel beside it")
	}
	if strings.Contains(view, "scroll readme") {
		t.Error("footer offers a scroll key for a panel that is not drawn")
	}
	// The table body only: the tab bar and the key legend are single long
	// strings that overflow a narrow terminal whatever the panel does.
	lines := strings.Split(view, "\n")
	for _, line := range lines[2 : len(lines)-3] {
		if w := lipgloss.Width(line); w > m.w {
			t.Errorf("table line %d cells wide, want at most %d: %q", w, m.w, line)
		}
	}
}

// A status message shares the footer with the selected app's context, so the
// next keypress has to clear it rather than leaving it there for good.
func TestStatusClearsOnNextKey(t *testing.T) {
	apps, err := LoadApps(appsDir)
	if err != nil {
		t.Fatal(err)
	}
	m := newModel(apps, appsDir, "tools", true)
	m.status, m.statusErr = "setup comfyui finished", false

	m.onKey(keyPress("j"))
	if m.status != "" {
		t.Errorf("status survived a keypress: %q", m.status)
	}
}

// Enter on the dashboard is setup: the wizard for an app with pages, the review
// screen for one without. It must never run anything unprompted.
func TestEnterOpensSetup(t *testing.T) {
	apps, err := LoadApps(appsDir)
	if err != nil {
		t.Fatal(err)
	}
	m := newModel(apps, appsDir, "tools", true)

	m.selectApp("dev-toolbox")
	m.onKey(keyPress("enter"))
	if m.wiz == nil || m.wiz.stage != stagePages {
		t.Fatal("enter did not open the wizard for an app with pages")
	}
	m.wizardKey("q")

	// An app with no wizard must still stop at the review screen rather than
	// launching a rebuild on one keypress. Which app that is changes as apps
	// gain wizards, so find one rather than naming it.
	var noWizard string
	for _, a := range apps {
		if !a.HasWizard {
			noWizard = a.Name
			break
		}
	}
	if noWizard == "" {
		t.Fatal("no wizard-less app to test the review screen with")
	}
	m.selectApp(noWizard)
	m.onKey(keyPress("enter"))
	if m.wiz == nil || m.wiz.stage != stageConfirm {
		t.Fatal("enter did not open the review screen for an app without pages")
	}
	if len(m.wiz.pages) != 0 {
		t.Errorf("expected no pages, got %d", len(m.wiz.pages))
	}
	// Esc is the only way back from a review screen with nothing behind it.
	m.wizardKey("esc")
	if m.wiz != nil {
		t.Error("esc did not close a review screen with no pages")
	}
}

// A confirmation with no answers behind it hands bash nothing: no state file,
// so the run is an ordinary `tools setup <app>`.
func TestConfirmOnlyRunNeedsNoStateFile(t *testing.T) {
	m := newModel([]App{}, appsDir, "tools", true)
	m.wiz = &wizardSession{app: App{Name: "comfyui"}, action: "setup", stage: stageConfirm}

	m.runWizardAction()
	if m.stateFile != "" {
		t.Errorf("wrote a state file for a wizard with no pages: %q", m.stateFile)
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
	m.wizardUpdate(wizItemsMsg{session: m.wiz.id, page: 0, values: []string{"v1", "v0"}})
	if m.wiz.page().loading {
		t.Fatal("page still loading after its items arrived")
	}
	m.wizardKey("enter")
	if m.wiz.stage != stageConfirm {
		t.Error("enter did not advance once the items had arrived")
	}
}

func TestWizTabLabel(t *testing.T) {
	cases := map[string]string{
		"00-release":     "Release",
		"01-statusline":  "Statusline",
		"00-tools":       "Tools",
		"00-gpu":         "GPU",
		"02-gpu-runtime": "GPU Runtime",
		"03-mcp":         "MCP",
		// Not an NN- prefix, so it is used as-is apart from casing.
		"custom": "Custom",
		"":       "",
	}
	for in, want := range cases {
		if got := wizTabLabel(in); got != want {
			t.Errorf("wizTabLabel(%q) = %q, want %q", in, got, want)
		}
	}
}

// twoPageSession builds a session with two pages, since no app in the repo is
// guaranteed to ship more than one and the tab bar is only interesting with
// several.
func twoPageSession(t *testing.T) *wizardSession {
	t.Helper()
	w, _ := newWizardSession(testApp(t, "codex-cli"), "setup", t.TempDir())
	second := w.pages[0]
	second.Name, second.Type = "01-statusline", "packages"
	second.items = []Item{{Name: "statusline"}}
	second.checked = []bool{false}
	second.loading = false
	w.pages[0].loading = false
	w.pages = append(w.pages, second)
	return w
}

// The highlighted tab must track the page, and Review must light up on the
// confirmation screen — a tab bar that does not move is worse than none.
func TestWizardTabsHighlightFollowsStage(t *testing.T) {
	m := newModel([]App{}, appsDir, "tools", true)
	m.w, m.h = 100, 24
	m.wiz = twoPageSession(t)

	active := func() string {
		bar := m.wizardTabsView()
		for _, label := range []string{"Release", "Statusline", "Review"} {
			if strings.Contains(bar, styTabOn.Render(label)) {
				return label
			}
		}
		return "none"
	}

	m.wiz.idx, m.wiz.stage = 0, stagePages
	if got := active(); got != "Release" {
		t.Errorf("page 0: active tab = %q, want Release", got)
	}
	m.wiz.idx = 1
	if got := active(); got != "Statusline" {
		t.Errorf("page 1: active tab = %q, want Statusline", got)
	}
	m.wiz.stage = stageConfirm
	if got := active(); got != "Review" {
		t.Errorf("confirm: active tab = %q, want Review", got)
	}
}

// ←/→ walk the pages and clamp at the ends: this is a linear flow, so wrapping
// from the first page to the last would skip everything between.
func TestWizardPageNavigationClamps(t *testing.T) {
	m := newModel([]App{}, appsDir, "tools", true)
	m.w, m.h = 100, 24
	m.wiz = twoPageSession(t)

	m.wizardKey("left")
	if m.wiz.idx != 0 || m.wiz.stage != stagePages {
		t.Errorf("left on page 0: idx=%d stage=%v, want 0/stagePages", m.wiz.idx, m.wiz.stage)
	}
	m.wizardKey("right")
	if m.wiz.idx != 1 {
		t.Fatalf("right: idx = %d, want 1", m.wiz.idx)
	}
	m.wizardKey("left")
	if m.wiz.idx != 0 {
		t.Errorf("left: idx = %d, want 0", m.wiz.idx)
	}
	// Past the last page, forward hands over to the confirmation screen.
	m.wizardKey("right")
	m.wizardKey("right")
	if m.wiz.stage != stageConfirm {
		t.Errorf("right past the last page: stage = %v, want stageConfirm", m.wiz.stage)
	}
}

// The header names the action. On the pages it is the only thing distinguishing
// a build wizard from a setup one — the review screen's actionNote() comes too
// late to help someone who opened the wrong one.
func TestWizardHeaderNamesTheAction(t *testing.T) {
	for _, action := range []string{"setup", "build", "create"} {
		m := newModel([]App{}, appsDir, "tools", true)
		m.w, m.h = 90, 24
		m.wiz, _ = newWizardSession(testApp(t, "comfyui"), action, t.TempDir())
		header := strings.SplitN(m.wizardView(), "\n", 2)[0]
		if !strings.Contains(header, "Wizard") || !strings.Contains(header, action) {
			t.Errorf("%s: header = %q, want it to name both Wizard and the action",
				action, stripStyles(header))
		}
	}
}

// stripStyles removes SGR escapes so a failure prints something readable.
func stripStyles(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == 0x1b {
			for i < len(s) && s[i] != 'm' {
				i++
			}
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}
