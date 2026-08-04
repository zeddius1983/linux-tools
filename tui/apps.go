package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// App is one entry under apps/.
type App struct {
	Name        string
	Description string
	Category    string
	HostOnly    bool
	HasImage    bool
	HasBox      bool
	BoxRunning  bool
	WizardDir   string
	Exports     []string
	HasWizard   bool
}

// UncategorisedLabel is used for apps with no apps/<name>/category file.
const UncategorisedLabel = "Other"

// Label is the display name: the human-friendly description when present,
// falling back to the directory name. The directory name remains the identity
// used for commands and paths.
func (a App) Label() string {
	if a.Description != "" {
		return a.Description
	}
	return a.Name
}

// ImageName mirrors image_name() in lib/helpers.sh.
func (a App) ImageName() string { return "linux-tools/" + a.Name + ":latest" }

// BoxName mirrors box_name() in lib/helpers.sh.
func (a App) BoxName() string { return a.Name + "-box" }

// Status is the short right-hand annotation shown next to an app in the list.
// Unlike the whiptail front-end this is not padded to a fixed width, so app
// descriptions are no longer constrained to ~26 characters.
func (a App) Status() string {
	if a.HostOnly {
		return "host"
	}
	switch {
	case a.BoxRunning:
		return "running"
	case a.HasBox:
		return "stopped"
	case a.HasImage:
		return "image only"
	default:
		return "—"
	}
}

// boxState is what `distrobox list` reports for one container.
type boxState struct {
	exists  bool
	running bool
}

func readExports(path string) []string {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var out []string
	for _, l := range strings.Split(string(b), "\n") {
		l = strings.TrimSpace(l)
		if l == "" || strings.HasPrefix(l, "#") {
			continue
		}
		out = append(out, l)
	}
	return out
}

// Categories returns the category names present, in a stable preferred order
// with any unknown ones appended alphabetically.
func Categories(apps []App) []string {
	preferred := []string{"AI / LLM", "Development", "System", "Browsers", "Communication", "Shell"}
	seen := map[string]bool{}
	for _, a := range apps {
		seen[a.Category] = true
	}
	var out []string
	for _, p := range preferred {
		if seen[p] {
			out = append(out, p)
			delete(seen, p)
		}
	}
	var rest []string
	for c := range seen {
		rest = append(rest, c)
	}
	sort.Strings(rest)
	return append(out, rest...)
}

// LoadApps discovers apps and annotates them with image/box state.
func LoadApps(appsDir string) ([]App, error) {
	entries, err := os.ReadDir(appsDir)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", appsDir, err)
	}

	images := podmanImages()
	boxes := distroboxNames()

	var apps []App
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		app := App{
			Name:      e.Name(),
			WizardDir: filepath.Join(appsDir, e.Name(), "wizard"),
		}
		app.Description = readTrimmed(filepath.Join(appsDir, e.Name(), "description"))
		app.Category = readTrimmed(filepath.Join(appsDir, e.Name(), "category"))
		if app.Category == "" {
			app.Category = UncategorisedLabel
		}
		if _, err := os.Stat(filepath.Join(appsDir, e.Name(), "host-only")); err == nil {
			app.HostOnly = true
		}
		if fi, err := os.Stat(app.WizardDir); err == nil && fi.IsDir() {
			app.HasWizard = true
		}
		app.Exports = readExports(filepath.Join(appsDir, e.Name(), "exports"))
		app.HasImage = images[app.ImageName()]
		app.HasBox, app.BoxRunning = boxes[app.BoxName()].exists, boxes[app.BoxName()].running
		apps = append(apps, app)
	}
	sort.Slice(apps, func(i, j int) bool { return apps[i].Name < apps[j].Name })
	return apps, nil
}

func readTrimmed(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// podmanImages returns the set of local image refs. A failure here is not
// fatal: status degrades to "not built" rather than blocking the menu, which
// keeps the binary usable when podman is unreachable (e.g. when it is run from
// inside a container during development).
func podmanImages() map[string]bool {
	out := map[string]bool{}
	cmd := hostCommand("podman", "images", "--format", "{{.Repository}}:{{.Tag}}")
	b, err := cmd.Output()
	if err != nil {
		return out
	}
	s := bufio.NewScanner(strings.NewReader(string(b)))
	for s.Scan() {
		ref := strings.TrimSpace(s.Text())
		out[ref] = true
		// Podman reports locally-built images with a "localhost/" prefix
		// ("localhost/linux-tools/comfyui:latest"), while image_name() in
		// lib/helpers.sh produces the unprefixed form. Index both so the
		// lookup matches either way.
		out[strings.TrimPrefix(ref, "localhost/")] = true
	}
	return out
}

// distroboxNames returns the state of every distrobox container.
func distroboxNames() map[string]boxState {
	out := map[string]boxState{}
	b, err := hostCommand("distrobox", "list", "--no-color").Output()
	if err != nil {
		return out
	}
	s := bufio.NewScanner(strings.NewReader(string(b)))
	for s.Scan() {
		// Rows are "ID | NAME | STATUS | IMAGE"; the header row is skipped
		// because it never matches a real box name.
		fields := strings.Split(s.Text(), "|")
		if len(fields) < 3 {
			continue
		}
		name := strings.TrimSpace(fields[1])
		if name == "" || name == "NAME" {
			continue
		}
		status := strings.ToLower(strings.TrimSpace(fields[2]))
		out[name] = boxState{exists: true, running: strings.HasPrefix(status, "up")}
	}
	return out
}
