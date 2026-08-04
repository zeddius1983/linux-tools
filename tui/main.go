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
	"os/exec"
	"sort"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

func main() {
	var appsDir, toolsBin string
	var render bool
	var renderApp string
	var renderW, renderH int
	flag.StringVar(&appsDir, "apps-dir", "apps", "path to the apps/ directory")
	flag.StringVar(&toolsBin, "tools", "tools", "bash entrypoint to run for actions")
	flag.BoolVar(&render, "render", false, "print one frame and exit (no tty needed)")
	flag.StringVar(&renderApp, "render-app", "", "select this app for --render")
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

	m := newModel(apps, appsDir, toolsBin)

	// --render draws a single frame to stdout. Bubble Tea needs a tty, so this
	// is the only way to check layout in a pipe, a test, or a screenshot.
	if render {
		m.w, m.h = renderW, renderH
		if renderApp != "" {
			m.selectApp(renderApp)
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
)

// --- model -------------------------------------------------------------------

type action struct {
	key, name, desc string
}

var actions = []action{
	{"s", "setup", "Install (removes existing box+image first)"},
	{"b", "build", "Build image only"},
	{"c", "create", "Create box from image"},
	{"e", "export", "Re-export to host"},
	{"r", "rm", "Remove box (image kept)"},
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
}

func newModel(apps []App, appsDir, toolsBin string) *model {
	return &model{
		apps:     apps,
		cats:     Categories(apps),
		appsDir:  appsDir,
		toolsBin: toolsBin,
		info:     newInfoPanel(appsDir),
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
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		return m, nil

	case actionDoneMsg:
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
	case "J", "pgdown", "ctrl+d":
		m.info.scroll(10)
	case "K", "pgup", "ctrl+u":
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
			return m, m.runCmd("enter", a, "distrobox", "enter", a.BoxName())
		}
		m.status, m.statusErr = "no box to enter", true
	default:
		for _, act := range actions {
			if k == act.key {
				if a, ok := m.current(); ok {
					return m, m.runCmd(act.name, a, m.toolsBin, act.name, a.Name)
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
// The wizard still runs on the bash side here: it sees a real tty, so
// whiptail behaves exactly as it does today.
func (m *model) runCmd(name string, a App, bin string, args ...string) tea.Cmd {
	c := exec.Command(bin, args...)
	c.Env = os.Environ()
	return tea.ExecProcess(c, func(err error) tea.Msg {
		return actionDoneMsg{action: name, app: a.Name, err: err}
	})
}

// --- view --------------------------------------------------------------------

// bodyHeight is the row budget for the table and info panel, after the tab bar
// and footer. Kept in one place so scrolling and rendering cannot disagree.
func (m *model) bodyHeight() int {
	h := m.h - 6
	if h < 4 {
		h = 4
	}
	return h
}

func (m *model) View() tea.View {
	if m.showHelp {
		return altView(m.helpView())
	}
	var b strings.Builder
	b.WriteString(m.tabsView())
	b.WriteString("\n")

	// Table on the left, README info panel on the right.
	infoW := m.infoWidth()
	tableW := m.w - infoW - 3
	body := lipgloss.JoinHorizontal(lipgloss.Top,
		lipgloss.NewStyle().Width(tableW).Render(m.tableView(tableW)),
		styBorder.Render(" │ "),
		m.infoView(infoW),
	)
	b.WriteString(body)
	b.WriteString("\n")
	b.WriteString(styBorder.Render(strings.Repeat("─", m.w)))
	b.WriteString("\n")
	b.WriteString(m.footerView())
	return altView(b.String())
}

// infoWidth is the README panel width: roughly 45% of the terminal, bounded so
// it neither starves the table nor becomes unreadably narrow.
func (m *model) infoWidth() int {
	w := m.w * 45 / 100
	if w < 34 {
		w = 34
	}
	if w > 72 {
		w = 72
	}
	if w > m.w-30 {
		w = m.w - 30
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

func (m *model) tabsView() string {
	var tabs []string
	for i, c := range m.cats {
		label := fmt.Sprintf("%s %d", c, m.countIn(c))
		if i == m.catIdx {
			tabs = append(tabs, styTabOn.Render(label))
		} else {
			tabs = append(tabs, styTabOff.Render(label))
		}
	}
	row := lipgloss.JoinHorizontal(lipgloss.Top, tabs...)
	return row + "\n" + styBorder.Render(strings.Repeat("─", m.w))
}

func (m *model) tableView(width int) string {
	v := m.visible()
	statusW := 11
	nameW := width - statusW - 5
	if nameW < 12 {
		nameW = 12
	}

	var b strings.Builder
	b.WriteString(styHeader.Render(fmt.Sprintf("  %-*s  %-*s", nameW, "APP", statusW, "STATUS")))
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
		line := fmt.Sprintf("%s %-*s  %-*s",
			marker(i == m.rowIdx),
			nameW, trunc(a.Label(), nameW),
			statusW, a.Status())
		if i == m.rowIdx {
			b.WriteString(styRowSel.Render(line))
		} else {
			b.WriteString(styRow.Render(line))
		}
		b.WriteString("\n")
	}
	if len(v) > h {
		b.WriteString(styDesc.Render(fmt.Sprintf("  %d-%d of %d", m.top+1, end, len(v))))
	}
	return b.String()
}

func (m *model) footerView() string {
	if m.filtering {
		return styKey.Render("/") + styRow.Render(m.filter) + styDesc.Render("  ⏎ apply · esc cancel")
	}
	if m.status != "" {
		st := styStatusOK
		if m.statusErr {
			st = styWarn
		}
		return st.Render("• "+m.status) + styDesc.Render("   ? help · q quit")
	}
	var parts []string
	for _, a := range actions {
		parts = append(parts, styKey.Render(a.key)+styDesc.Render(" "+a.name))
	}
	parts = append(parts,
		styKey.Render("⏎")+styDesc.Render(" shell"),
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
		{"J / K, pgdn / pgup", "scroll the README panel"},
		{"/", "filter within category"},
		{"s", "setup — install (removes existing box+image)"},
		{"b", "build — image only"},
		{"c", "create — box from image"},
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

func marker(sel bool) string {
	if sel {
		return "▸"
	}
	return " "
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
