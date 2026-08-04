// Command tools-tui is the Go + huh front-end for linux-tools.
//
// It is a pre-processor, not a wrapper: it collects the app, the action and
// every wizard answer, writes them to a state file, and then execs the bash
// backend. Bubble Tea is fully torn down before the build runs, so podman
// output streams to the terminal exactly as it does today. See
// docs/tui-migration.md §3.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/huh/spinner"
)

var actions = []struct{ Name, Desc string }{
	{"setup", "Install (removes existing box+image first)"},
	{"build", "Build container image only"},
	{"create", "Create distrobox from built image"},
	{"export", "Re-export apps/bins to host"},
	{"enter", "Open shell inside box"},
	{"rm", "Remove distrobox (image is kept)"},
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

func run(appsDir, statePath, toolsBin string, dryRun bool) error {
	apps, err := LoadApps(appsDir)
	if err != nil {
		return err
	}
	if len(apps) == 0 {
		return fmt.Errorf("no apps found in %s", appsDir)
	}

	// --- app + action -----------------------------------------------------
	var appName, action string

	appOpts := make([]huh.Option[string], 0, len(apps))
	for _, a := range apps {
		label := a.Name
		if a.Description != "" {
			label += " — " + a.Description
		}
		// No padding, no truncation: the 26-char description budget that
		// whiptail's fixed columns imposed is simply gone.
		label += "  [" + a.Status() + "]"
		appOpts = append(appOpts, huh.NewOption(label, a.Name))
	}

	actionOpts := make([]huh.Option[string], 0, len(actions))
	for _, a := range actions {
		actionOpts = append(actionOpts, huh.NewOption(a.Name+" — "+a.Desc, a.Name))
	}

	pick := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("linux-tools").
				Description("Select an app (type to filter)").
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
	)
	if err := pick.Run(); err != nil {
		return handleAbort(err)
	}

	// --- wizard pages -----------------------------------------------------
	var app App
	for _, a := range apps {
		if a.Name == appName {
			app = a
		}
	}

	state := State{App: appName, Action: action, Pages: map[string][]string{}}
	pages, err := LoadPages(app.WizardDir)
	if err != nil {
		return err
	}

	home, _ := os.UserHomeDir()
	var groups []*huh.Group
	// Bindings keep each page's live value addressable after the form runs.
	multi := map[string]*[]string{}
	single := map[string]*string{}

	for _, p := range pages {
		if !p.AppliesTo(action) {
			continue
		}
		switch p.Type {
		case "packages", "mcp":
			opts := make([]huh.Option[string], 0, len(p.Items))
			for _, it := range p.Items {
				label := it.Name
				if it.Desc != "" {
					label += " — " + it.Desc
				}
				opts = append(opts, huh.NewOption(label, it.Name).Selected(it.PreSelected(home)))
			}
			if len(opts) == 0 {
				continue
			}
			dst := new([]string)
			multi[p.Name] = dst
			groups = append(groups, huh.NewGroup(
				huh.NewMultiSelect[string]().
					Title(p.Title).
					Description(p.Prompt).
					Options(opts...).
					Height(14).
					Value(dst),
			))

		case "runtime":
			opts := make([]huh.Option[string], 0, len(p.Items))
			for _, it := range p.Items {
				label := it.Name
				if it.Desc != "" {
					label += " — " + it.Desc
				}
				// The Option carries label and value together, so there is no
				// label->value round-trip like wizard_create_variant needs.
				opts = append(opts, huh.NewOption(label, it.Payload))
			}
			if len(opts) == 0 {
				continue
			}
			dst := new(string)
			single[p.Name] = dst
			groups = append(groups, huh.NewGroup(
				huh.NewSelect[string]().
					Title(p.Title).
					Description(p.Prompt).
					Options(opts...).
					Value(dst),
			))

		case "buildarg":
			// items-cmd is often a network call (fastflowlm hits the GitHub
			// releases API). whiptail froze silently here; a spinner makes the
			// wait visible.
			var values []string
			var cmdErr error
			_ = spinner.New().
				Title(" " + p.Title + ": fetching options…").
				Action(func() { values, cmdErr = runItemsCmd(p.ItemsCmd) }).
				Run()
			if cmdErr != nil || len(values) == 0 {
				fmt.Fprintf(os.Stderr,
					"warning: wizard page %q: items-cmd produced no items, using build default\n", p.Name)
				continue
			}
			opts := make([]huh.Option[string], 0, len(values))
			for i, v := range values {
				label := v
				if i == 0 {
					label += "  (default)"
				}
				opts = append(opts, huh.NewOption(label, v))
			}
			dst := new(string)
			*dst = values[0]
			single[p.Name] = dst
			groups = append(groups, huh.NewGroup(
				huh.NewSelect[string]().
					Title(p.Title).
					Description(p.Prompt).
					Options(opts...).
					Height(14).
					Value(dst),
			))
		}
	}

	if len(groups) > 0 {
		// One form, many groups: unlike whiptail's standalone dialogs this
		// gives back-navigation across pages for free.
		if err := huh.NewForm(groups...).Run(); err != nil {
			return handleAbort(err)
		}
	}

	// --- resolve selections into the state --------------------------------
	for _, p := range pages {
		if !p.AppliesTo(action) {
			continue
		}
		switch p.Type {
		case "packages", "mcp":
			if dst, ok := multi[p.Name]; ok {
				state.Pages[p.Name] = *dst
			}
		case "runtime":
			if dst, ok := single[p.Name]; ok && *dst != "" {
				state.Variant = *dst
			}
		case "buildarg":
			if dst, ok := single[p.Name]; ok && *dst != "" && p.ArgName != "" {
				state.BuildArgs = append(state.BuildArgs,
					"--build-arg", p.ArgName+"="+*dst)
			}
		}
	}

	// --- confirm ----------------------------------------------------------
	confirmed := false
	if err := huh.NewForm(huh.NewGroup(
		huh.NewConfirm().
			Title(fmt.Sprintf("Run '%s' on '%s'?", action, appName)).
			Description(summarize(state)).
			Affirmative("Yes").
			Negative("Cancel").
			Value(&confirmed),
	)).Run(); err != nil {
		return handleAbort(err)
	}
	if !confirmed {
		return nil
	}

	// --- hand off to bash -------------------------------------------------
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

func summarize(s State) string {
	var parts []string
	for name, sel := range s.Pages {
		if len(sel) > 0 {
			parts = append(parts, name+": "+strings.Join(sel, ", "))
		} else {
			parts = append(parts, name+": (none)")
		}
	}
	if s.Variant != "" {
		parts = append(parts, "variant: "+s.Variant)
	}
	if len(s.BuildArgs) > 0 {
		parts = append(parts, "build: "+strings.Join(s.BuildArgs, " "))
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
