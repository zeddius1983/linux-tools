// Command tools-tui is the dashboard front-end for linux-tools.
//
// Layout follows gh-dash: a category tab bar, a table of apps, a detail pane
// for the selected row, and a keybinding footer. Actions suspend the dashboard
// with tea.ExecProcess, hand the terminal to the bash backend so podman output
// streams normally, then resume — so the dashboard survives a build rather
// than exec'ing away.
package main

import (
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

func main() {
	var appsDir, toolsBin string
	var render, asciiIcons bool
	var renderApp, renderWizard string
	var renderW, renderH int
	flag.StringVar(&appsDir, "apps-dir", "apps", "path to the apps/ directory")
	flag.StringVar(&toolsBin, "tools", "tools", "bash entrypoint to run for actions")
	flag.BoolVar(&asciiIcons, "ascii", false, "plain ASCII/Unicode markers instead of Nerd Font glyphs")
	flag.BoolVar(&render, "render", false, "print one frame and exit (no tty needed)")
	flag.StringVar(&renderApp, "render-app", "", "select this app for --render")
	flag.StringVar(&renderWizard, "render-wizard", "", "open the wizard for this action (setup|build|create) in --render")
	flag.IntVar(&renderW, "render-width", 100, "frame width for --render")
	flag.IntVar(&renderH, "render-height", 28, "frame height for --render")
	flag.Parse()

	apps, err := LoadApps(appsDir)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
	if len(apps) == 0 {
		fmt.Fprintf(os.Stderr, "no apps found in %s\n", appsDir)
		os.Exit(1)
	}

	m := newModel(apps, appsDir, toolsBin, !asciiIcons)

	// --render draws a single frame to stdout. Bubble Tea needs a tty, so this
	// is the only way to check layout in a pipe, a test, or a screenshot.
	if render {
		m.w, m.h = renderW, renderH
		if renderApp != "" {
			m.selectApp(renderApp)
		}
		if renderWizard != "" {
			// Draw the wizard instead of the dashboard. Any items-cmd is left
			// unresolved: the command returned here would normally be run by
			// the event loop, and a single frame has none.
			if a, ok := m.current(); ok {
				m.startWizard(action{name: renderWizard, wizard: true}, a)
			}
		}
		fmt.Println(m.View().Content)
		return
	}

	if _, err := tea.NewProgram(m).Run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

// --- theme -------------------------------------------------------------------

var (
	colFg       = lipgloss.Color("#ebdbb2")
	colDim      = lipgloss.Color("#928374")
	colAccent   = lipgloss.Color("#fabd2f")
	colOK       = lipgloss.Color("#b8bb26")
	colWarn     = lipgloss.Color("#fe8019")
	colBorder   = lipgloss.Color("#504945")
	colGlyph    = lipgloss.Color("#83a598") // gruvbox blue, shared by tab and row glyphs
	colSelBg    = lipgloss.Color("#3c3836")
	styTabOn    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#1d2021")).Background(colAccent).Padding(0, 1)
	styTabOff   = lipgloss.NewStyle().Foreground(colDim).Padding(0, 1)
	styHeader   = lipgloss.NewStyle().Bold(true).Foreground(colDim)
	styRow      = lipgloss.NewStyle().Foreground(colFg)
	styRowSel   = lipgloss.NewStyle().Foreground(colAccent).Background(colSelBg).Bold(true)
	styBorder   = lipgloss.NewStyle().Foreground(colBorder)
	styKey      = lipgloss.NewStyle().Bold(true).Foreground(colAccent)
	styDesc     = lipgloss.NewStyle().Foreground(colDim)
	styTitle    = lipgloss.NewStyle().Bold(true).Foreground(colFg)
	styStatusOK = lipgloss.NewStyle().Foreground(colOK)
	styStatusNo = lipgloss.NewStyle().Foreground(colDim)
	styWarn     = lipgloss.NewStyle().Foreground(colWarn)
	// One colour for every glyph, tab bar and rows alike, so they read as a set.
	// The shape already says container vs host, so colour only has to make them
	// legible — the dim style used before rendered Docker's logo nearly
	// invisible. The active tab keeps its inverted styling, since a blue glyph
	// on the accent background would lose contrast.
	styGlyph = lipgloss.NewStyle().Foreground(colGlyph)
)

// --- model -------------------------------------------------------------------

type action struct {
	key, name, desc string
	// wizard marks actions that wizard pages can declare themselves applicable
	// to. It mirrors tools.sh: setup asks and applies, while build and create
	// only consume what a state file already holds.
	wizard bool
}

var actions = []action{
	{"s", "setup", "Install (removes existing box+image first)", true},
	{"b", "build", "Build image only", true},
	{"c", "create", "Create box from image", true},
	{"e", "export", "Re-export to host", false},
	{"r", "rm", "Remove box (image kept)", false},
}

type model struct {
	apps     []App
	cats     []string
	appsDir  string
	toolsBin string

	catIdx int
	rowIdx int
	top    int // first visible row, for scrolling

	w, h      int
	filter    string
	filtering bool
	showHelp  bool
	status    string
	statusErr bool
	info      *infoPanel
	icons     iconSet

	// wiz is the open wizard session, if any: while it is non-nil it owns the
	// screen and every key. stateFile is the file it wrote for the run
	// currently in flight, removed once that run finishes.
	wiz       *wizardSession
	stateFile string
}

func newModel(apps []App, appsDir, toolsBin string, useNerdFonts bool) *model {
	return &model{
		apps:     apps,
		cats:     Categories(apps),
		appsDir:  appsDir,
		toolsBin: toolsBin,
		info:     newInfoPanel(appsDir),
		icons:    newIconSet(useNerdFonts),
		w:        100,
		h:        30,
	}
}

func (m *model) Init() tea.Cmd { return nil }

// selectApp moves the cursor to a named app, switching category if needed.
func (m *model) selectApp(name string) bool {
	for ci := range m.cats {
		m.catIdx = ci
		for ri, a := range m.visible() {
			if a.Name == name {
				m.rowIdx = ri
				m.clampRow()
				return true
			}
		}
	}
	m.catIdx = 0
	return false
}

// visible returns the apps in the current category matching the filter.
func (m *model) visible() []App {
	if len(m.cats) == 0 {
		return nil
	}
	cat := m.cats[m.catIdx]
	var out []App
	f := strings.ToLower(m.filter)
	for _, a := range m.apps {
		if a.Category != cat {
			continue
		}
		if f != "" && !strings.Contains(strings.ToLower(a.Name+" "+a.Label()), f) {
			continue
		}
		out = append(out, a)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Label() < out[j].Label() })
	return out
}

func (m *model) current() (App, bool) {
	v := m.visible()
	if m.rowIdx < 0 || m.rowIdx >= len(v) {
		return App{}, false
	}
	return v[m.rowIdx], true
}

// countIn is the per-category app count shown in the tab bar.
func (m *model) countIn(cat string) int {
	n := 0
	for _, a := range m.apps {
		if a.Category == cat {
			n++
		}
	}
	return n
}

type reloadMsg struct{}
type actionDoneMsg struct {
	action, app string
	err         error
}

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// An open wizard owns the screen and every key until it is confirmed or
	// cancelled; only the action result, which arrives after it has closed,
	// bypasses it.
	if m.wiz != nil {
		if _, ok := msg.(actionDoneMsg); !ok {
			return m.wizardUpdate(msg)
		}
	}
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		return m, nil

	case actionDoneMsg:
		// The state file exists only for the duration of one run; leaving it
		// behind would have no effect (the backend only reads it when
		// LT_WIZARD_STATE points at it) but it would still be stale answers on
		// disk.
		if m.stateFile != "" {
			os.Remove(m.stateFile)
			m.stateFile = ""
		}
		if msg.err != nil {
			m.status = fmt.Sprintf("%s %s failed: %v", msg.action, msg.app, msg.err)
			m.statusErr = true
		} else {
			m.status = fmt.Sprintf("%s %s finished", msg.action, msg.app)
			m.statusErr = false
		}
		// Container state almost certainly changed; re-read it.
		if apps, err := LoadApps(m.appsDir); err == nil {
			m.apps = apps
			m.cats = Categories(apps)
		}
		return m, nil

	case tea.KeyPressMsg:
		return m.onKey(msg)
	}
	return m, nil
}

func (m *model) onKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	k := msg.String()

	// Filter entry swallows most keys.
	if m.filtering {
		switch k {
		case "enter", "esc":
			m.filtering = false
		case "backspace":
			if m.filter != "" {
				m.filter = m.filter[:len(m.filter)-1]
			}
		case "ctrl+c":
			return m, tea.Quit
		default:
			if len(k) == 1 {
				m.filter += k
			}
		}
		m.clampRow()
		return m, nil
	}

	switch k {
	case "q", "esc", "ctrl+c":
		return m, tea.Quit
	case "?":
		m.showHelp = !m.showHelp
	case "/":
		m.filtering = true
		m.filter = ""
	case "tab", "l", "right":
		if len(m.cats) > 0 {
			m.catIdx = (m.catIdx + 1) % len(m.cats)
			m.rowIdx, m.top = 0, 0
			m.info.resetScroll()
		}
	case "shift+tab", "h", "left":
		if len(m.cats) > 0 {
			m.catIdx = (m.catIdx - 1 + len(m.cats)) % len(m.cats)
			m.rowIdx, m.top = 0, 0
			m.info.resetScroll()
		}
	case "j", "down":
		m.rowIdx++
		m.clampRow()
		m.info.resetScroll()
	case "k", "up":
		m.rowIdx--
		m.clampRow()
		m.info.resetScroll()
	case "pgdown":
		m.info.scroll(10)
	case "pgup":
		m.info.scroll(-10)
	case "g", "home":
		m.rowIdx, m.top = 0, 0
		m.info.resetScroll()
	case "end":
		m.rowIdx = len(m.visible()) - 1
		m.clampRow()
		m.info.resetScroll()
	case "R":
		if apps, err := LoadApps(m.appsDir); err == nil {
			m.apps = apps
			m.cats = Categories(apps)
			m.status, m.statusErr = "reloaded", false
		}
	case "enter":
		if a, ok := m.current(); ok && a.HasBox {
			return m, m.runCmd("enter", a, nil, "distrobox", "enter", a.BoxName())
		}
		m.status, m.statusErr = "no box to enter", true
	default:
		for _, act := range actions {
			if k == act.key {
				if a, ok := m.current(); ok {
					// Actions that can carry wizard answers open the wizard
					// first; startWizard falls through to the plain run when
					// the app has no pages for this action.
					if act.wizard {
						return m, m.startWizard(act, a)
					}
					return m, m.runCmd(act.name, a, nil, m.toolsBin, act.name, a.Name)
				}
			}
		}
	}
	return m, nil
}

func (m *model) clampRow() {
	n := len(m.visible())
	if n == 0 {
		m.rowIdx, m.top = 0, 0
		return
	}
	if m.rowIdx < 0 {
		m.rowIdx = 0
	}
	if m.rowIdx >= n {
		m.rowIdx = n - 1
	}
	h := m.bodyHeight() - 1
	if m.rowIdx < m.top {
		m.top = m.rowIdx
	}
	if m.rowIdx >= m.top+h {
		m.top = m.rowIdx - h + 1
	}
	if m.top < 0 {
		m.top = 0
	}
}

// runCmd suspends the dashboard, gives bash the terminal, then resumes.
//
// extraEnv carries the wizard bridge (LT_SKIP_WIZARD, LT_WIZARD_STATE) when
// answers were collected here. Without it bash sees a real tty and asks its own
// whiptail pages, which is still the right behaviour for an app whose wizard
// this front-end skipped.
func (m *model) runCmd(name string, a App, extraEnv []string, bin string, args ...string) tea.Cmd {
	c := hostCommand(bin, args...)
	c.Env = append(os.Environ(), extraEnv...)
	return tea.ExecProcess(c, func(err error) tea.Msg {
		return actionDoneMsg{action: name, app: a.Name, err: err}
	})
}

// --- view --------------------------------------------------------------------

// bodyHeight is the row budget for the table and info panel, after the tab bar
// and footer. Kept in one place so scrolling and rendering cannot disagree.
func (m *model) bodyHeight() int {
	// tab bar (2) + divider (1) + footer (2) + slack
	h := m.h - 7
	if h < 4 {
		h = 4
	}
	return h
}

func (m *model) View() tea.View {
	if m.wiz != nil {
		return altView(m.wizardView())
	}
	if m.showHelp {
		return altView(m.helpView())
	}
	var b strings.Builder
	b.WriteString(m.tabsView())
	b.WriteString("\n")

	// Table on the left, README info panel on the right.
	infoW := m.infoWidth()
	tableW := m.w - infoW - 3
	// The divider must be built as a column of its own. JoinHorizontal pads a
	// single-line element with blanks on every following line rather than
	// repeating it, so " │ " on its own drew the separator only on row one.
	// Its height is taken from the taller of the two panes, since the table
	// gains an extra line when it shows a "n-m of N" counter.
	table, info := m.tableView(tableW), m.infoView(infoW)
	rows := maxInt(strings.Count(table, "\n")+1, strings.Count(info, "\n")+1)
	divider := make([]string, rows)
	for i := range divider {
		divider[i] = styBorder.Render(" │ ")
	}
	body := lipgloss.JoinHorizontal(lipgloss.Top,
		lipgloss.NewStyle().Width(tableW).Render(table),
		strings.Join(divider, "\n"),
		info,
	)
	b.WriteString(body)
	b.WriteString("\n")
	b.WriteString(styBorder.Render(strings.Repeat("─", m.w)))
	b.WriteString("\n")
	b.WriteString(m.footerView())
	return altView(b.String())
}

// infoWidth is the README panel width: roughly 60% of the terminal, bounded so
// it neither starves the table nor becomes unreadably narrow.
func (m *model) infoWidth() int {
	w := m.w * 60 / 100
	if w < 40 {
		w = 40
	}
	if w > 96 {
		w = 96
	}
	// The table still needs room for the app label plus both state columns.
	if w > m.w-48 {
		w = m.w - 48
	}
	if w < 20 {
		w = 20
	}
	return w
}

func (m *model) infoView(width int) string {
	a, ok := m.current()
	if !ok {
		return lipgloss.NewStyle().Width(width).Render(styDesc.Render("no app selected"))
	}
	return m.info.view(a, width, m.bodyHeight())
}

// superscript renders an integer with Unicode superscript digits, so the count
// sits above the baseline next to the tab name instead of taking a whole word.
func superscript(n int) string {
	digits := []rune("⁰¹²³⁴⁵⁶⁷⁸⁹")
	if n == 0 {
		return string(digits[0])
	}
	var out []rune
	for _, c := range fmt.Sprintf("%d", n) {
		out = append(out, digits[c-'0'])
	}
	return string(out)
}

func (m *model) tabsView() string {
	var tabs []string
	for i, c := range m.cats {
		g, name := m.icons.category(c), c+superscript(m.countIn(c))
		if i == m.catIdx {
			tabs = append(tabs, styTabOn.Render(g+name))
		} else {
			// Glyph in the shared accent, label dim: the same pairing the rows
			// use, so an inactive tab and a row read alike.
			tabs = append(tabs,
				styTabOff.UnsetPadding().PaddingLeft(1).Foreground(colGlyph).Render(g)+
					styTabOff.UnsetPadding().PaddingRight(1).Render(name))
		}
	}
	row := lipgloss.JoinHorizontal(lipgloss.Top, tabs...)
	return row + "\n" + styBorder.Render(strings.Repeat("─", m.w))
}

func (m *model) tableView(width int) string {
	v := m.visible()
	// Both columns are glyph-only: IMAGE has two states and BOX three, few
	// enough that a word adds nothing. Every value is one cell, so the glyphs
	// align down the column by construction — right-aligning "✓ built" against
	// a bare "✗" is what left them ragged before. The help overlay carries the
	// legend.
	imgW, boxW := 5, 3
	// Gap between the two state columns. They are only a glyph wide each, so a
	// single space read as one column rather than two.
	const colGap = 4
	// Both the header and the rows open with a 4-cell prefix — "    " above,
	// gutter + glyph + space below — so the APP field must be the same width in
	// each, or the state columns start two cells later on rows than in the
	// header.
	nameW := width - imgW - boxW - colGap - 5
	if nameW < 12 {
		nameW = 12
	}

	var b strings.Builder
	// State columns are right-aligned, header and values alike: the values vary
	// in length ("✓ built" vs a bare "✗"), so left-aligning left the header
	// visibly offset from the text beneath it.
	b.WriteString(styHeader.Render(fmt.Sprintf("    %-*s %s%s%s",
		nameW, "APP", "IMAGE", strings.Repeat(" ", colGap), "BOX")))
	b.WriteString("\n")

	if len(v) == 0 {
		b.WriteString(styDesc.Render("  (no apps match)"))
		return b.String()
	}

	h := m.bodyHeight() - 1
	end := m.top + h
	if end > len(v) {
		end = len(v)
	}
	for i := m.top; i < end; i++ {
		a := v[i]
		sel := i == m.rowIdx

		glyph, glyphSty := m.icons.appGlyph(a)
		imgTxt, imgSty := m.icons.image(a)
		boxTxt, boxSty := m.icons.box(a)

		// The selected row is marked by a background running the full width
		// rather than a leading arrow. Each segment keeps its own foreground —
		// state colour stays readable — and only gains the background, because
		// wrapping an already-styled string would be cut short by its resets.
		on := func(st lipgloss.Style) lipgloss.Style {
			if sel {
				return st.Background(colSelBg).Bold(true)
			}
			return st
		}
		plain := lipgloss.NewStyle()
		nameSty := styRow
		if sel {
			nameSty = lipgloss.NewStyle().Foreground(colAccent)
		}

		label := trunc(a.Label(), nameW)
		used := 4 + nameW + 1 + imgW + colGap + boxW
		trail := maxInt(width-used, 0)

		b.WriteString(on(plain).Render("  "))
		b.WriteString(on(glyphSty).Render(glyph))
		b.WriteString(on(plain).Render(" "))
		b.WriteString(on(nameSty).Render(pad(label, nameW)))
		b.WriteString(on(plain).Render(" "))
		b.WriteString(on(imgSty).Render(padCenter(imgTxt, imgW)))
		b.WriteString(on(plain).Render(strings.Repeat(" ", colGap)))
		b.WriteString(on(boxSty).Render(padCenter(boxTxt, boxW)))
		b.WriteString(on(plain).Render(strings.Repeat(" ", trail)))
		b.WriteString("\n")
	}
	if len(v) > h {
		b.WriteString(styDesc.Render(fmt.Sprintf("  %d-%d of %d", m.top+1, end, len(v))))
	}
	return b.String()
}

// padCenter centres text in w cells, so a one-cell glyph sits under the middle
// of its header.
func padCenter(s string, w int) string {
	n := len([]rune(s))
	if n >= w {
		return s
	}
	left := (w - n) / 2
	return strings.Repeat(" ", left) + s + strings.Repeat(" ", w-n-left)
}

// padLeft left-pads to w cells, right-aligning the text.
func padLeft(s string, w int) string {
	n := len([]rune(s))
	if n >= w {
		return s
	}
	return strings.Repeat(" ", w-n) + s
}

// pad right-pads to w display cells, counting runes rather than bytes.
func pad(s string, w int) string {
	n := len([]rune(s))
	if n >= w {
		return s
	}
	return s + strings.Repeat(" ", w-n)
}

// footerView renders two lines: what the selected app is, then the keys.
func (m *model) footerView() string {
	return m.contextLine() + "\n" + m.keysLine()
}

// contextLine shows the selected app's image reference and the commands it
// exports to the host — the two things you usually want before running an
// action on it.
func (m *model) contextLine() string {
	if m.filtering {
		return styKey.Render("/") + styRow.Render(m.filter) +
			styDesc.Render("   ⏎ apply · esc cancel")
	}
	if m.status != "" {
		st := styStatusOK
		if m.statusErr {
			st = styWarn
		}
		return st.Render("• " + m.status)
	}

	a, ok := m.current()
	if !ok {
		return ""
	}

	var img string
	switch {
	case a.HostOnly:
		img = styDesc.Render("installs to the host")
	case a.HasImage:
		img = styStatusOK.Render(a.ImageName())
	default:
		img = styStatusNo.Render(a.ImageName() + " (not built)")
	}

	exports := a.ExportNames()
	if len(exports) == 0 {
		return img
	}
	// Exports can be long; the image reference is the more important half, so
	// the command list is what gets clipped.
	room := m.w - lipgloss.Width(img) - 5
	return img + styDesc.Render("   ⇥ ") +
		styRow.Render(trunc(strings.Join(exports, " "), maxInt(room, 10)))
}

func (m *model) keysLine() string {
	var parts []string
	for _, a := range actions {
		parts = append(parts, styKey.Render(a.key)+styDesc.Render(" "+a.name))
	}
	parts = append(parts,
		styKey.Render("⏎")+styDesc.Render(" shell"),
		styKey.Render("PgDn/PgUp")+styDesc.Render(" scroll readme"),
		styKey.Render("/")+styDesc.Render(" filter"),
		styKey.Render("?")+styDesc.Render(" help"),
		styKey.Render("q")+styDesc.Render(" quit"),
	)
	return strings.Join(parts, styDesc.Render(" · "))
}

func (m *model) helpView() string {
	var b strings.Builder
	b.WriteString(styTitle.Render("linux-tools — keys") + "\n\n")
	rows := [][2]string{
		{"↑/k  ↓/j", "move selection"},
		{"←/h  →/l", "previous / next category"},
		{"tab / shift+tab", "previous / next category"},
		{"g / end", "first / last row"},
		{"PgDn / PgUp", "scroll the README panel"},
		{"/", "filter within category"},
		{"s", "setup — install (removes existing box+image)"},
		{"b", "build — image only"},
		{"c", "create — box from image"},
		{"", "s/b/c open the app's wizard first when it has pages"},
		{"e", "export — re-export to host"},
		{"r", "rm — remove box, keep image"},
		{"⏎", "open a shell in the box"},
		{"R", "reload app/container state"},
		{"?", "toggle this help"},
		{"q / esc", "quit"},
	}
	for _, r := range rows {
		b.WriteString(fmt.Sprintf("  %s  %s\n",
			styKey.Render(fmt.Sprintf("%-16s", r[0])), styDesc.Render(r[1])))
	}
	b.WriteString("\n" + styTitle.Render("  columns") + "\n\n")
	legend := [][2]string{
		{"IMAGE  ✓", "image built"},
		{"IMAGE  ✗", "not built"},
		{"BOX    ●", "box exists and is running"},
		{"BOX    ○", "box exists, stopped"},
		{"BOX    ✗", "no box"},
		{"(blank)", "host-only app — no image or box"},
	}
	for _, r := range legend {
		b.WriteString(fmt.Sprintf("  %s  %s\n",
			styKey.Render(fmt.Sprintf("%-16s", r[0])), styDesc.Render(r[1])))
	}
	b.WriteString("\n" + styDesc.Render("  Actions hand the terminal to the bash backend and return here when done."))
	return b.String()
}

// altView renders full-screen. In bubbletea v2 the alt screen is a property of
// the View rather than a program option, so it is set on every render.
func altView(content string) tea.View {
	v := tea.NewView(content)
	v.AltScreen = true
	return v
}

func trunc(s string, w int) string {
	if w <= 1 || len([]rune(s)) <= w {
		return s
	}
	return string([]rune(s)[:w-1]) + "…"
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
