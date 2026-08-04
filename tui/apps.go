package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// App is one entry under apps/.
type App struct {
	Name        string
	Description string
	HostOnly    bool
	HasImage    bool
	HasBox      bool
	WizardDir   string
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
	case a.HasBox:
		return "installed"
	case a.HasImage:
		return "image only"
	default:
		return "not built"
	}
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
		if _, err := os.Stat(filepath.Join(appsDir, e.Name(), "host-only")); err == nil {
			app.HostOnly = true
		}
		app.HasImage = images[app.ImageName()]
		app.HasBox = boxes[app.BoxName()]
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
	cmd := exec.Command("podman", "images", "--format", "{{.Repository}}:{{.Tag}}")
	b, err := cmd.Output()
	if err != nil {
		return out
	}
	s := bufio.NewScanner(strings.NewReader(string(b)))
	for s.Scan() {
		out[strings.TrimSpace(s.Text())] = true
	}
	return out
}

// distroboxNames returns the set of existing distrobox container names.
func distroboxNames() map[string]bool {
	out := map[string]bool{}
	b, err := exec.Command("distrobox", "list", "--no-color").Output()
	if err != nil {
		return out
	}
	s := bufio.NewScanner(strings.NewReader(string(b)))
	for s.Scan() {
		// Rows are "ID | NAME | STATUS | IMAGE"; the header row is skipped
		// because it never matches a real box name.
		fields := strings.Split(s.Text(), "|")
		if len(fields) < 2 {
			continue
		}
		if name := strings.TrimSpace(fields[1]); name != "" {
			out[name] = true
		}
	}
	return out
}
