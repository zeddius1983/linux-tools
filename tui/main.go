// Command tools-tui is the Go + huh front-end for linux-tools.
//
// It is a pre-processor, not a wrapper: it collects the app, the action and
// every wizard answer, writes them to a state file, and then execs the bash
// backend. Bubble Tea is fully torn down before the build runs, so podman
// output streams to the terminal exactly as today. See docs/tui-migration.md.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/huh"
)

var actions = []struct{ Name, Desc string }{
	{"setup", "Install (removes existing box+image first)"},
	{"build", "Build container image only"},
	{"create", "Create distrobox from built image"},
	{"export", "Re-export apps/bins to host"},
	{"enter", "Open shell inside box"},
	{"rm", "Remove distrobox (image is kept)"},
}

// keyMap advertises the keys the default huh map leaves invisible.
//
// huh v0.7.0 binds Quit to ctrl+c only, and without a help string, so nothing
// in the UI tells you how to leave. Esc is not bound to quit at all. Both are
// bound here, and the help line is left on so back/quit are discoverable.
func keyMap() *huh.KeyMap {
	km := huh.NewDefaultKeyMap()
	km.Quit = key.NewBinding(
		key.WithKeys("esc", "ctrl+c"),
		key.WithHelp("esc", "quit"),
	)
	return km
}

func main() {
	var appsDir, statePath, toolsBin string
	var dryRun bool
	flag.StringVar(&appsDir, "apps-dir", "apps", "path to the apps/ directory")
	flag.StringVar(&statePath, "state", "", "state file path (default: XDG_RUNTIME_DIR/linux-tools/wizard-<app>.state)")
	flag.StringVar(&toolsBin, "tools", "tools", "bash entrypoint to exec")
	flag.BoolVar(&dryRun, "dry-run", false, "write and print the state file, then exit without exec")
	flag.Parse()

	if err := run(appsDir, statePath, toolsBin, dryRun); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

// binding holds the live value of one wizard page within the form.
type binding struct {
	page   Page
	app    string
	multi  *[]string
	single *string
}

func run(appsDir, statePath, toolsBin string, dryRun bool) error {
	apps, err := LoadApps(appsDir)
	if err != nil {
		return err
	}
	if len(apps) == 0 {
		return fmt.Errorf("no apps found in %s", appsDir)
	}

	var appName, action string
	var confirmed bool
	home, _ := os.UserHomeDir()

	// --- app + action groups ----------------------------------------------
	appOpts := make([]huh.Option[string], 0, len(apps))
	for _, a := range apps {
		label := a.Name
		if a.Description != "" {
			label += " — " + a.Description
		}
		// No padding, no truncation: the ~26-char description budget that
		// whiptail's fixed columns imposed is gone.
		label += "  [" + a.Status() + "]"
		appOpts = append(appOpts, huh.NewOption(label, a.Name))
	}
	actionOpts := make([]huh.Option[string], 0, len(actions))
	for _, a := range actions {
		actionOpts = append(actionOpts, huh.NewOption(a.Name+" — "+a.Desc, a.Name))
	}

	groups := []*huh.Group{
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("linux-tools").
				Description("Select an app  ·  / filters  ·  shift+tab goes back  ·  esc quits").
				Options(appOpts...).
				Filtering(true).
				Height(16).
				Value(&appName),
		),
		huh.NewGroup(
			huh.NewSelect[string]().
				TitleFunc(func() string { return "linux-tools — " + appName }, &appName).
				Description("Choose action").
				Options(actionOpts...).
				Height(10).
				Value(&action),
		),
	}

	// --- one group per wizard page, across every app ----------------------
	//
	// The whole flow has to live in a single huh.Form for shift+tab to walk
	// backwards across stages, but the relevant wizard pages are not known
	// until an app is picked. So every page of every app becomes a group that
	// hides itself unless its app is selected and its action applies.
	var bindings []*binding
	for _, a := range apps {
		pages, err := LoadPages(a.WizardDir)
		if err != nil {
			return err
		}
		for _, p := range pages {
			g, b := pageGroup(a.Name, p, home, &appName, &action)
			if g == nil {
				continue
			}
			groups = append(groups, g)
			bindings = append(bindings, b)
		}
	}

	// --- confirm ----------------------------------------------------------
	groups = append(groups, huh.NewGroup(
		huh.NewConfirm().
			TitleFunc(func() string {
				return fmt.Sprintf("Run '%s' on '%s'?", action, appName)
			}, &appName).
			DescriptionFunc(func() string {
				return summarize(collect(appName, action, bindings))
			}, &appName).
			Affirmative("Yes").
			Negative("Cancel").
			Value(&confirmed),
	))

	form := huh.NewForm(groups...).
		WithKeyMap(keyMap()).
		WithShowHelp(true)
	if err := form.Run(); err != nil {
		return handleAbort(err)
	}
	if !confirmed {
		return nil
	}

	// --- hand off to bash -------------------------------------------------
	state := collect(appName, action, bindings)
	if statePath == "" {
		statePath = DefaultStatePath(appName)
	}
	if err := state.Write(statePath); err != nil {
		return err
	}

	if dryRun {
		fmt.Printf("state written to %s\n\n%s\n", statePath, state.Render())
		fmt.Printf("would exec: %s %s %s\n", toolsBin, action, appName)
		return nil
	}

	bin, err := exec.LookPath(toolsBin)
	if err != nil {
		return fmt.Errorf("locating %q: %w", toolsBin, err)
	}
	env := append(os.Environ(),
		"LT_WIZARD_STATE="+statePath,
		"LT_SKIP_WIZARD=1",
	)
	// Exec and never return: bash owns the terminal from here.
	return syscallExec(bin, []string{toolsBin, action, appName}, env)
}

// pageGroup builds the hidden-until-relevant group for one wizard page.
func pageGroup(app string, p Page, home string, appName, action *string) (*huh.Group, *binding) {
	b := &binding{page: p, app: app}
	hide := func() bool { return *appName != app || !p.AppliesTo(*action) }

	switch p.Type {
	case "packages", "mcp":
		if len(p.Items) == 0 {
			return nil, nil
		}
		opts := make([]huh.Option[string], 0, len(p.Items))
		for _, it := range p.Items {
			opts = append(opts, huh.NewOption(label(it), it.Name).Selected(it.PreSelected(home)))
		}
		b.multi = new([]string)
		return huh.NewGroup(
			huh.NewMultiSelect[string]().
				Title(p.Title).
				Description(p.Prompt).
				Options(opts...).
				Height(14).
				Value(b.multi),
		).WithHideFunc(hide), b

	case "runtime":
		if len(p.Items) == 0 {
			return nil, nil
		}
		opts := make([]huh.Option[string], 0, len(p.Items))
		for _, it := range p.Items {
			// The Option carries label and value together, so there is no
			// label->value round-trip like wizard_create_variant needs.
			opts = append(opts, huh.NewOption(label(it), it.Payload))
		}
		b.single = new(string)
		*b.single = p.Items[0].Payload
		return huh.NewGroup(
			huh.NewSelect[string]().
				Title(p.Title).
				Description(p.Prompt).
				Options(opts...).
				Value(b.single),
		).WithHideFunc(hide), b

	case "buildarg":
		b.single = new(string)
		return huh.NewGroup(
			huh.NewSelect[string]().
				Title(p.Title).
				Description(p.Prompt).
				// Lazily fetched: items-cmd is often a network call (fastflowlm
				// hits the GitHub releases API). Binding it to appName keeps
				// the fetch from running for apps that were never selected,
				// and huh shows its own loading state while it runs.
				OptionsFunc(func() []huh.Option[string] {
					if *appName != app {
						return nil
					}
					values, err := runItemsCmd(p.ItemsCmd)
					if err != nil || len(values) == 0 {
						return nil
					}
					opts := make([]huh.Option[string], 0, len(values))
					for i, v := range values {
						l := v
						if i == 0 {
							l += "  (default)"
						}
						opts = append(opts, huh.NewOption(l, v))
					}
					return opts
				}, appName).
				Height(14).
				Value(b.single),
		).WithHideFunc(hide), b
	}
	return nil, nil
}

func label(it Item) string {
	if it.Desc == "" {
		return it.Name
	}
	return it.Name + " — " + it.Desc
}

// collect turns the live form bindings into a State for the selected app.
func collect(appName, action string, bindings []*binding) State {
	s := State{App: appName, Action: action, Pages: map[string][]string{}}
	for _, b := range bindings {
		if b.app != appName || !b.page.AppliesTo(action) {
			continue
		}
		switch b.page.Type {
		case "packages", "mcp":
			if b.multi != nil {
				s.Pages[b.page.Name] = *b.multi
			}
		case "runtime":
			if b.single != nil && *b.single != "" {
				s.Variant = *b.single
			}
		case "buildarg":
			if b.single != nil && *b.single != "" && b.page.ArgName != "" {
				s.BuildArgs = append(s.BuildArgs, "--build-arg", b.page.ArgName+"="+*b.single)
			}
		}
	}
	return s
}

func summarize(s State) string {
	var parts []string
	names := make([]string, 0, len(s.Pages))
	for k := range s.Pages {
		names = append(names, k)
	}
	sort.Strings(names)
	for _, n := range names {
		if sel := s.Pages[n]; len(sel) > 0 {
			parts = append(parts, n+": "+strings.Join(sel, ", "))
		} else {
			parts = append(parts, n+": (none)")
		}
	}
	if s.Variant != "" {
		parts = append(parts, "variant: "+s.Variant)
	}
	if len(s.BuildArgs) > 0 {
		parts = append(parts, "build: "+strings.Join(s.BuildArgs, " "))
	}
	if len(parts) == 0 {
		return "No wizard selections for this app."
	}
	return strings.Join(parts, "\n")
}

func runItemsCmd(cmd string) ([]string, error) {
	if strings.TrimSpace(cmd) == "" {
		return nil, nil
	}
	out, err := exec.Command("bash", "-c", cmd).Output()
	if err != nil {
		return nil, err
	}
	var values []string
	for _, l := range strings.Split(string(out), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			values = append(values, l)
		}
	}
	return values, nil
}

// handleAbort turns a user abort into a clean exit rather than an error.
func handleAbort(err error) error {
	if err == huh.ErrUserAborted {
		os.Exit(0)
	}
	return err
}
