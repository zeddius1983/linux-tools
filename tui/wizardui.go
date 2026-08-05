package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

// Native wizard pages: the last thing the bash whiptail front-end was still
// doing. Answers are collected here, written to a state file, and handed to the
// backend through LT_WIZARD_STATE / LT_SKIP_WIZARD — see docs/tui-migration.md
// §2 for why the state file has to exist at all.

// wizStage is which screen a session is showing.
type wizStage int

const (
	stagePages wizStage = iota
	stageConfirm
)

// wizPage pairs a parsed page with the answer being collected for it.
//
// .packages and .mcp are checklists; .buildarg and .runtime are single choice.
// Only .buildarg resolves its items at wizard time, by running the page's
// items-cmd — so it is the only one that can be empty, slow, or fail.
type wizPage struct {
	Page
	items   []Item
	checked []bool
	radio   int
	loading bool
	loadErr error
}

func (p wizPage) multi() bool { return p.Type == "packages" || p.Type == "mcp" }

type wizardSession struct {
	id     int
	app    App
	action string
	pages  []wizPage
	idx    int
	cursor int
	stage  wizStage
	home   string
}

// wizItemsMsg carries the result of a .buildarg page's items-cmd.
//
// session identifies the wizard that asked. items-cmd takes seconds, and a
// user who cancels one wizard and opens another before it returns would
// otherwise have the first app's releases land in the second app's page —
// matched on page index alone, which every session has.
type wizItemsMsg struct {
	session int
	page    int
	values  []string
	err     error
}

// wizSessions numbers wizard sessions so their async results can be told apart.
var wizSessions int

// newWizardSession builds a session for the pages that apply to this action,
// returning nil when the app has none — the caller then runs the action
// directly, exactly as before.
func newWizardSession(a App, action, home string) (*wizardSession, tea.Cmd) {
	if !a.HasWizard {
		return nil, nil
	}
	pages, err := LoadPages(a.WizardDir)
	if err != nil || len(pages) == 0 {
		return nil, nil
	}

	wizSessions++
	w := &wizardSession{id: wizSessions, app: a, action: action, home: home}
	var cmds []tea.Cmd
	for _, p := range pages {
		if !p.AppliesTo(action) {
			continue
		}
		wp := wizPage{Page: p}
		switch p.Type {
		case "buildarg":
			if p.ArgName == "" || p.ItemsCmd == "" {
				continue
			}
			wp.loading = true
			cmds = append(cmds, loadBuildArgItems(w.id, len(w.pages), p.ItemsCmd))
		default:
			// A page whose body has no items is skipped, mirroring the empty
			// item-list guard in _wizard_run_page.
			if len(p.Items) == 0 {
				continue
			}
			wp.items = p.Items
			wp.checked = make([]bool, len(p.Items))
			for i, it := range p.Items {
				wp.checked[i] = it.PreSelected(home)
			}
		}
		w.pages = append(w.pages, wp)
	}
	if len(w.pages) == 0 {
		return nil, nil
	}
	return w, tea.Batch(cmds...)
}

// loadBuildArgItems runs a page's items-cmd. The command is the app's own — it
// reaches the network (a GitHub API call, a git ls-remote), so it is run off
// the update loop and bounded by a timeout rather than left to hang the UI.
func loadBuildArgItems(session, page int, cmdline string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		out, err := hostCommandContext(ctx, "bash", "-c", cmdline).Output()
		if err != nil {
			return wizItemsMsg{session: session, page: page, err: err}
		}
		var vals []string
		for _, l := range strings.Split(string(out), "\n") {
			if l = strings.TrimSpace(l); l != "" {
				vals = append(vals, l)
			}
		}
		return wizItemsMsg{session: session, page: page, values: vals}
	}
}

func (w *wizardSession) page() *wizPage {
	if w.idx < 0 || w.idx >= len(w.pages) {
		return nil
	}
	return &w.pages[w.idx]
}

// window is the slice of the current page's items to draw for a viewport of
// rows lines, keeping the cursor inside it.
func (w *wizardSession) window(rows int) (top, end int) {
	p := w.page()
	if p == nil {
		return 0, 0
	}
	n := len(p.items)
	if rows >= n {
		return 0, n
	}
	// Centre the cursor once the list is longer than the viewport, so there is
	// context on both sides of it rather than only above.
	top = w.cursor - rows/2
	if top < 0 {
		top = 0
	}
	if top > n-rows {
		top = n - rows
	}
	return top, top + rows
}

// wizardRows is how many item rows fit on screen: the terminal less the app
// header and its rule (3), the page title, prompt and the blank after it (3),
// the row counter (1), the packages footnote and its blank (2), and the rule
// above the key legend plus the legend itself (2).
//
// It is the same budget for a page that has no footnote, which just leaves a
// blank line — better than a page that runs one line past the bottom.
func (m *model) wizardRows() int {
	rows := m.h - 11
	if rows < 3 {
		rows = 3
	}
	return rows
}

// focus puts the cursor where the page's answer already is, so arriving at a
// single-choice page — forwards or backwards — highlights the current choice
// rather than resetting to the top.
func (w *wizardSession) focus() {
	w.cursor = 0
	if p := w.page(); p != nil && !p.multi() && p.radio < len(p.items) {
		w.cursor = maxInt(p.radio, 0)
	}
}

// ready reports whether the current page can be advanced past. A .buildarg page
// that is still loading holds the wizard; one that failed does not, because the
// bash path also carries on and lets the Dockerfile default stand.
func (w *wizardSession) ready() bool {
	p := w.page()
	return p == nil || !p.loading
}

// diff summarises what the run will change, mirroring tui_confirm_wizards.
// Only .packages pages have an on-disk notion of "already installed".
func (w *wizardSession) diff() (install, remove []string) {
	for _, p := range w.pages {
		if p.Type != "packages" {
			continue
		}
		for i, it := range p.items {
			label := it.Name
			if it.Desc != "" {
				label += " — " + it.Desc
			}
			switch installed := it.Installed(w.home); {
			case p.checked[i] && !installed:
				install = append(install, label)
			case !p.checked[i] && installed:
				remove = append(remove, label)
			}
		}
	}
	return install, remove
}

// state resolves every answer into the form the bash backend consumes: build
// args already rendered as tokens, the runtime variant as its value rather than
// its label, and one PAGE_ entry per page.
//
// Pages are written even when nothing is selected. An empty entry is the
// deselect-everything answer, and the apply handlers act on it — dropping it
// would silently turn "remove all of these" into "change nothing".
func (w *wizardSession) state() State {
	st := State{App: w.app.Name, Action: w.action, Pages: map[string][]string{}}
	for _, p := range w.pages {
		switch {
		case p.multi():
			sel := []string{}
			for i, it := range p.items {
				if p.checked[i] {
					sel = append(sel, it.Name)
				}
			}
			st.Pages[p.Name] = sel
		case len(p.items) == 0 || p.radio < 0 || p.radio >= len(p.items):
			// items-cmd produced nothing: leave the page unanswered so the
			// build falls back to its default, as the bash path does.
		case p.Type == "runtime":
			it := p.items[p.radio]
			st.Variant = it.Payload
			st.Pages[p.Name] = []string{it.Name}
		case p.Type == "buildarg":
			v := p.items[p.radio].Name
			st.BuildArgs = append(st.BuildArgs, "--build-arg", p.ArgName+"="+v)
			st.Pages[p.Name] = []string{v}
		}
	}
	return st
}

// --- model integration -------------------------------------------------------

// startWizard opens the wizard for an action. An app with no pages for it
// still gets the review screen when the action asks for one; otherwise the
// action runs straight away.
func (m *model) startWizard(act action, a App) tea.Cmd {
	home, _ := os.UserHomeDir()
	w, cmd := newWizardSession(a, act.name, home)
	if w == nil {
		if !act.confirm {
			return m.runCmd(act.name, a, nil, m.toolsBin, act.name, a.Name)
		}
		// Nothing to ask, but still something to confirm: open straight on the
		// review screen. It carries no answers, so the run gets no state file
		// and behaves exactly like a plain `tools <action> <app>`.
		w = &wizardSession{app: a, action: act.name, home: home, stage: stageConfirm}
	}
	m.wiz = w
	m.status = ""
	return cmd
}

// wizardUpdate owns every message while a session is open.
func (m *model) wizardUpdate(msg tea.Msg) (tea.Model, tea.Cmd) {
	w := m.wiz
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		return m, nil

	case wizItemsMsg:
		// A result from a wizard that has since been cancelled and replaced
		// belongs to a different app; page index alone does not say that.
		if msg.session != w.id || msg.page < 0 || msg.page >= len(w.pages) {
			return m, nil
		}
		p := &w.pages[msg.page]
		p.loading = false
		p.loadErr = msg.err
		p.items = nil
		for _, v := range msg.values {
			p.items = append(p.items, Item{Name: v})
		}
		// items-cmd prints the preferred value first; it is the default.
		p.radio = 0
		return m, nil

	case tea.KeyPressMsg:
		return m.wizardKey(msg.String())

	case tea.MouseWheelMsg:
		// The wheel moves the cursor, the same as j/k. Toggling still takes a
		// deliberate keypress: a wheel click is too easy to fire by accident on
		// a screen where every row changes what gets installed.
		switch msg.Button {
		case tea.MouseWheelUp:
			return m.wizardKey("k")
		case tea.MouseWheelDown:
			return m.wizardKey("j")
		}
	}
	return m, nil
}

func (m *model) wizardKey(k string) (tea.Model, tea.Cmd) {
	w := m.wiz

	if w.stage == stageConfirm {
		switch k {
		case "enter", "y":
			return m, m.runWizardAction()
		case "esc", "backspace", "left", "h":
			// With no pages behind it the review screen is the whole wizard, so
			// going "back" is leaving.
			if len(w.pages) == 0 {
				m.wiz = nil
				return m, nil
			}
			w.stage = stagePages
			w.focus()
			return m, nil
		case "ctrl+c", "q":
			m.wiz = nil
			return m, nil
		}
		return m, nil
	}

	p := w.page()
	n := 0
	if p != nil {
		n = len(p.items)
	}

	switch k {
	case "ctrl+c", "q":
		// No status message: the dashboard reappearing is the acknowledgement,
		// and nothing happened that the footer needs to report.
		m.wiz = nil
	case "esc":
		// Back a page, or out of the wizard from the first one.
		if w.idx == 0 {
			m.wiz = nil
			return m, nil
		}
		w.idx--
		w.focus()
	case "j", "down":
		if n > 0 {
			w.cursor = (w.cursor + 1) % n
		}
	case "k", "up":
		if n > 0 {
			w.cursor = (w.cursor - 1 + n) % n
		}
	case "g", "home":
		w.cursor = 0
	case "end":
		w.cursor = maxInt(n-1, 0)
	case "space", "x":
		if p == nil || n == 0 {
			break
		}
		if p.multi() {
			p.checked[w.cursor] = !p.checked[w.cursor]
		} else {
			p.radio = w.cursor
		}
	case "a":
		if p != nil && p.multi() {
			for i := range p.checked {
				p.checked[i] = true
			}
		}
	case "n":
		if p != nil && p.multi() {
			for i := range p.checked {
				p.checked[i] = false
			}
		}
	case "enter", "right", "l":
		if !w.ready() {
			break
		}
		// On a single-choice page the cursor is the answer, so Enter commits
		// it: requiring Space first is a trap when the highlight already looks
		// like a selection.
		if p != nil && !p.multi() && n > 0 {
			p.radio = w.cursor
		}
		if w.idx+1 < len(w.pages) {
			w.idx++
			w.focus()
		} else {
			w.stage = stageConfirm
		}
	}
	return m, nil
}

// runWizardAction writes the state file and hands the terminal to bash.
// LT_SKIP_WIZARD tells tools.sh the answers are already collected, so the
// whiptail pages are not asked a second time.
func (m *model) runWizardAction() tea.Cmd {
	w := m.wiz
	m.wiz = nil

	// A confirmation with no pages behind it has nothing to hand over: run it
	// as a plain `tools <action> <app>` rather than writing an empty state file
	// that only tells bash to skip a wizard that does not exist.
	var env []string
	if len(w.pages) > 0 {
		path, err := w.state().WriteNew()
		if err != nil {
			m.status, m.statusErr = "could not write wizard state: "+err.Error(), true
			return nil
		}
		m.stateFile = path
		env = []string{"LT_SKIP_WIZARD=1", "LT_WIZARD_STATE=" + path}
	}
	return m.runCmd(w.action, w.app, env, m.toolsBin, w.action, w.app.Name)
}

// --- view --------------------------------------------------------------------

func (m *model) wizardView() string {
	w := m.wiz
	var b strings.Builder

	b.WriteString(styTabOn.Render(" "+w.app.Label()+" ") +
		styDesc.Render("  "+w.action))
	if w.stage == stagePages {
		b.WriteString(styDesc.Render(fmt.Sprintf("   step %d/%d", w.idx+1, len(w.pages))))
	}
	b.WriteString("\n" + styBorder.Render(strings.Repeat("─", m.w)) + "\n\n")

	if w.stage == stageConfirm {
		b.WriteString(m.wizardConfirmBody())
	} else {
		b.WriteString(m.wizardPageBody())
	}

	b.WriteString("\n" + styBorder.Render(strings.Repeat("─", m.w)) + "\n")
	b.WriteString(m.wizardKeys())
	return b.String()
}

func (m *model) wizardPageBody() string {
	w := m.wiz
	p := w.page()
	if p == nil {
		return ""
	}

	var b strings.Builder
	b.WriteString("  " + styTitle.Render(p.Title) + "\n")
	b.WriteString("  " + styDesc.Render(p.Prompt) + "\n\n")

	switch {
	case p.loading:
		b.WriteString("  " + styDesc.Render("loading available versions…") + "\n")
		return b.String()
	case len(p.items) == 0:
		msg := "no versions available — the build default will be used"
		if p.loadErr != nil {
			msg = "could not list versions (" + p.loadErr.Error() + ") — the build default will be used"
		}
		b.WriteString("  " + styWarn.Render(msg) + "\n")
		return b.String()
	}

	// Widest name, so the descriptions line up in a column of their own.
	nameW := 0
	for _, it := range p.items {
		nameW = maxInt(nameW, len([]rune(it.Name)))
	}
	nameW = minInt(nameW, 28)

	// Only as many rows as the screen has room for, following the cursor. The
	// shipped shell-toolbox page has 18 items, which runs off a 24-line
	// terminal and takes the footer — the keys telling you how to get out —
	// with it.
	top, end := w.window(m.wizardRows())

	for i := top; i < end; i++ {
		it := p.items[i]
		marker := m.icons.wizMarker(p.multi(), p.multi() && p.checked[i] || !p.multi() && p.radio == i)

		nameSty, descSty := styRow, styDesc
		cursor := "  "
		if i == w.cursor {
			cursor = styKey.Render("❯ ")
			nameSty = lipgloss.NewStyle().Foreground(colAccent).Bold(true)
		}
		markSty := styStatusNo
		if p.multi() && p.checked[i] || !p.multi() && p.radio == i {
			markSty = styStatusOK
		}

		b.WriteString("  " + cursor + markSty.Render(marker) + " " +
			nameSty.Render(pad(trunc(it.Name, nameW), nameW)))
		if it.Desc != "" {
			room := maxInt(m.w-nameW-12, 10)
			b.WriteString("  " + descSty.Render(trunc(it.Desc, room)))
		}
		b.WriteString("\n")
	}

	if end-top < len(p.items) {
		b.WriteString(styDesc.Render(fmt.Sprintf("    %d-%d of %d", top+1, end, len(p.items))) + "\n")
	}

	// Detect-driven pages start with what is already on disk ticked, which is
	// worth saying: unticking a row is how you remove it, not just how you skip
	// it.
	if p.Type == "packages" {
		b.WriteString("\n  " + styDesc.Render("ticked = installed after this run; unticking an installed tool removes it"))
	}
	return b.String()
}

func (m *model) wizardConfirmBody() string {
	w := m.wiz
	install, remove := w.diff()
	st := w.state()

	var b strings.Builder
	b.WriteString("  " + styTitle.Render("Confirm") + "\n\n")

	// What the action itself does, before any wizard answers. setup is the
	// destructive one — it removes the existing image and box first — and that
	// is the whole reason this screen appears for apps with no pages at all.
	if note := w.actionNote(); note != "" {
		b.WriteString("  " + note + "\n")
		if len(install) > 0 || len(remove) > 0 {
			b.WriteString("\n")
		}
	}

	if len(install) > 0 {
		b.WriteString("  " + styStatusOK.Render("Installing:") + "\n")
		for _, s := range install {
			b.WriteString("    " + styStatusOK.Render("+") + " " + styRow.Render(s) + "\n")
		}
	}
	if len(remove) > 0 {
		if len(install) > 0 {
			b.WriteString("\n")
		}
		b.WriteString("  " + styWarn.Render("Removing:") + "\n")
		for _, s := range remove {
			b.WriteString("    " + styWarn.Render("-") + " " + styRow.Render(s) + "\n")
		}
	}
	if len(st.BuildArgs) > 0 {
		b.WriteString("\n  " + styDesc.Render("Build arg:") + " " +
			styRow.Render(strings.Join(st.BuildArgs[1:], " ")) + "\n")
	}
	if st.Variant != "" {
		// The label is what was chosen; the value is what bash acts on, and
		// seeing both is how you tell the two apart when they differ.
		label := st.Variant
		for _, p := range w.pages {
			if p.Type == "runtime" && p.radio < len(p.items) {
				label = p.items[p.radio].Name
			}
		}
		b.WriteString("  " + styDesc.Render("Runtime:  ") + " " + styRow.Render(label) +
			styDesc.Render(" ("+st.Variant+")") + "\n")
	}
	b.WriteString("\n  " + styDesc.Render(fmt.Sprintf("runs: tools %s %s", w.action, w.app.Name)) + "\n")
	return b.String()
}

// actionNote describes the action's own effect on this app, which is the only
// content the review screen has for an app with no wizard pages.
func (w *wizardSession) actionNote() string {
	switch w.action {
	case "setup":
		if w.app.HostOnly {
			return styRow.Render("Installs to the host.")
		}
		if w.app.HasImage || w.app.HasBox {
			return styWarn.Render("Removes the existing image and box") +
				styRow.Render(", then rebuilds and re-exports.")
		}
		return styRow.Render("Builds the image, creates the box and exports it to the host.")
	case "build":
		return styRow.Render("Builds the image. The box is left as it is.")
	case "create":
		if w.app.HasBox {
			return styWarn.Render("Replaces the existing box") + styRow.Render(" from the built image.")
		}
		return styRow.Render("Creates the box from the built image.")
	}
	return ""
}

func (m *model) wizardKeys() string {
	w := m.wiz
	var parts []string
	if w.stage == stageConfirm {
		parts = []string{styKey.Render("⏎") + styDesc.Render(" proceed")}
		if len(w.pages) > 0 {
			parts = append(parts,
				styKey.Render("esc")+styDesc.Render(" back"),
				styKey.Render("q")+styDesc.Render(" cancel"))
		} else {
			// Nothing behind this screen, so esc leaves outright.
			parts = append(parts, styKey.Render("q/esc")+styDesc.Render(" cancel"))
		}
	} else {
		p := w.page()
		if p != nil && p.multi() {
			parts = append(parts,
				styKey.Render("space")+styDesc.Render(" toggle"),
				styKey.Render("a/n")+styDesc.Render(" all/none"))
		} else {
			parts = append(parts, styKey.Render("space")+styDesc.Render(" select"))
		}
		next := " next"
		if w.idx+1 == len(w.pages) {
			next = " review"
		}
		parts = append(parts,
			styKey.Render("↑/↓")+styDesc.Render(" move"),
			styKey.Render("⏎")+styDesc.Render(next))
		if w.idx == 0 {
			// There is no page behind the first one, so esc leaves outright.
			parts = append(parts, styKey.Render("q/esc")+styDesc.Render(" cancel"))
		} else {
			parts = append(parts,
				styKey.Render("esc")+styDesc.Render(" back"),
				styKey.Render("q")+styDesc.Render(" cancel"))
		}
	}
	return strings.Join(parts, styDesc.Render(" · "))
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
