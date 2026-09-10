package main

import (
	"bufio"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Item is one selectable row in a wizard page body.
type Item struct {
	Name      string
	Payload   string
	Desc      string
	DefaultOn bool
	Detect    []string // .packages only

	// .buildarg only, and only when the page names a release source: the
	// markdown body of the release this value installs, with the release's own
	// title above it. Both are empty for a value with no matching release.
	Notes      string
	NotesTitle string
}

// Page is a parsed apps/<app>/wizard/NN-name.<type> file.
//
// Header is fixed at three lines (title, prompt, applicable actions); the body
// grammar varies by type, which is exactly why parsing lives here and not in
// bash as well — see docs/tui-migration.md §4.
type Page struct {
	File       string
	Name       string // "00-statusline"
	Type       string // "packages" | "buildarg" | "runtime" | "mcp"
	Title      string
	Prompt     string
	Applicable []string // "*" means every action
	Items      []Item

	// .buildarg config
	ArgName  string
	ItemsCmd string

	// .buildarg release sources. ReleasesRepo ("owner/repo") replaces ItemsCmd
	// entirely — the tags and their notes both come from one API call.
	// NotesRepo instead decorates an ItemsCmd list with notes, for pages whose
	// values come from somewhere else (git tags, a hard-coded "latest").
	ReleasesRepo  string
	ReleasesLimit int
	NotesRepo     string
	NotesTag      string // tag template, "%s" = the item value
	NotesLimit    int
	Extra         []string // literal values appended after the fetched releases
}

// AppliesTo mirrors the action gate in _wizard_run_page.
func (p Page) AppliesTo(action string) bool {
	for _, a := range p.Applicable {
		if a == "*" || a == action {
			return true
		}
	}
	return false
}

// LoadPages parses every wizard page for an app, in filename order.
func LoadPages(wizardDir string) ([]Page, error) {
	matches, err := filepath.Glob(filepath.Join(wizardDir, "[0-9][0-9]-*.*"))
	if err != nil || len(matches) == 0 {
		return nil, err
	}
	sort.Strings(matches)

	var pages []Page
	for _, m := range matches {
		p, err := parsePage(m)
		if err != nil {
			return nil, err
		}
		pages = append(pages, p)
	}
	return pages, nil
}

func parsePage(path string) (Page, error) {
	f, err := os.Open(path)
	if err != nil {
		return Page{}, err
	}
	defer f.Close()

	base := filepath.Base(path)
	ext := strings.TrimPrefix(filepath.Ext(base), ".")
	p := Page{
		File: path,
		Name: strings.TrimSuffix(base, filepath.Ext(base)),
		Type: ext,
	}

	var lines []string
	s := bufio.NewScanner(f)
	for s.Scan() {
		// Strip CR so CRLF files parse, matching the bash implementation.
		lines = append(lines, strings.TrimRight(s.Text(), "\r"))
	}
	if len(lines) < 3 {
		return p, nil
	}

	p.Title, p.Prompt = lines[0], lines[1]
	for _, a := range strings.Split(lines[2], ",") {
		if a = strings.TrimSpace(a); a != "" {
			p.Applicable = append(p.Applicable, a)
		}
	}

	for _, line := range lines[3:] {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "|")

		if p.Type == "buildarg" {
			// Body lines are config, not items.
			if len(fields) >= 2 {
				switch strings.TrimSpace(fields[0]) {
				case "arg":
					p.ArgName = strings.TrimSpace(fields[1])
				case "items-cmd":
					// Rejoin: the command itself may contain '|'.
					p.ItemsCmd = strings.Join(fields[1:], "|")
				case "releases":
					p.ReleasesRepo = strings.TrimSpace(fields[1])
					if len(fields) > 2 {
						p.ReleasesLimit = atoiOr(fields[2], 0)
					}
				case "notes-repo":
					p.NotesRepo = strings.TrimSpace(fields[1])
					if len(fields) > 2 {
						p.NotesTag = strings.TrimSpace(fields[2])
					}
					if len(fields) > 3 {
						p.NotesLimit = atoiOr(fields[3], 0)
					}
				case "extra":
					if v := strings.TrimSpace(fields[1]); v != "" {
						p.Extra = append(p.Extra, v)
					}
				}
			}
			continue
		}

		// A .runtime page may additionally name a build arg, so one choice can
		// drive both the create-time variant and the image build (e.g. comfyui's
		// AMD/NVIDIA pick, which selects a base image *and* GPU passthrough).
		// "arg" is therefore reserved and cannot be an option label here.
		if p.Type == "runtime" && len(fields) >= 2 && strings.TrimSpace(fields[0]) == "arg" {
			p.ArgName = strings.TrimSpace(fields[1])
			continue
		}

		it := Item{Name: fields[0]}
		if len(fields) > 1 {
			it.Payload = fields[1]
		}
		if len(fields) > 2 {
			it.Desc = fields[2]
		}
		if len(fields) > 3 {
			it.DefaultOn = strings.EqualFold(strings.TrimSpace(fields[3]), "on")
		}
		if len(fields) > 4 && fields[4] != "" {
			for _, d := range strings.Split(fields[4], ",") {
				if d = strings.TrimSpace(d); d != "" {
					it.Detect = append(it.Detect, d)
				}
			}
		}
		p.Items = append(p.Items, it)
	}
	return p, nil
}

// Installed reports whether a .packages item is already present on disk.
//
// A bare detect entry is checked as ~/.local/bin/<name>; a "~/" prefix expands
// to $HOME. Any match wins. When a detect field exists it is the sole
// authority and DefaultOn is ignored, so uninstalled tools always start
// unchecked — same rule as _wizard_run_page.
// HasSource reports whether a .buildarg page knows where to get its items.
func (p Page) HasSource() bool {
	return p.ArgName != "" && (p.ItemsCmd != "" || p.ReleasesRepo != "")
}

// atoiOr parses a small positive count, falling back on anything unparseable —
// a typo in a page's limit should cost the default, not the page.
func atoiOr(s string, fallback int) int {
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil || n <= 0 {
		return fallback
	}
	return n
}

func (i Item) Installed(home string) bool {
	for _, d := range i.Detect {
		var path string
		if strings.HasPrefix(d, "~/") {
			path = filepath.Join(home, d[2:])
		} else {
			path = filepath.Join(home, ".local", "bin", d)
		}
		if _, err := os.Lstat(path); err == nil {
			return true
		}
	}
	return false
}

// PreSelected is the initial checkbox state for a .packages item.
func (i Item) PreSelected(home string) bool {
	if len(i.Detect) > 0 {
		return i.Installed(home)
	}
	return i.DefaultOn
}
