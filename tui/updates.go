package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
)

// The background half of the per-app update check: fetching each installed
// release-picker app's versions, and caching the answer.
//
// The versions come from the app's own wizard pages, exactly as the picker
// lists them, so "an update" means a newer version the picker would offer —
// nothing has to be configured per app, and the picker's filters (codex's
// stable-only tags, orca's tag-match) decide what counts.

const (
	// appUpdateEvery is how long an answer is reused. Upstream releases land
	// daily at most for most of these apps, and every check costs at least one
	// GitHub API call per app against an anonymous 60/hour.
	appUpdateEvery = 6 * time.Hour
	// appUpdateTimeout bounds one app's check: an items-cmd's git ls-remote,
	// then a notes lookup.
	appUpdateTimeout = 60 * time.Second
)

// appUpdateMsg carries one app's answer back to the event loop.
type appUpdateMsg struct {
	app string
	upd appUpdate
}

type appUpdateCache struct {
	CheckedAt time.Time `json:"checked_at"`
	Release   string    `json:"release"` // the installed release it was computed for
	Update    appUpdate `json:"update"`
}

func appUpdateCachePath(app string) string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return ""
		}
		base = filepath.Join(home, ".cache")
	}
	return filepath.Join(base, "linux-tools", "updates", app+".json")
}

func readAppUpdateCache(app, release string) (appUpdate, bool) {
	path := appUpdateCachePath(app)
	if path == "" {
		return appUpdate{}, false
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return appUpdate{}, false
	}
	var c appUpdateCache
	if json.Unmarshal(b, &c) != nil || c.Release != release || time.Since(c.CheckedAt) > appUpdateEvery {
		return appUpdate{}, false
	}
	return c.Update, true
}

func writeAppUpdateCache(app, release string, u appUpdate) {
	path := appUpdateCachePath(app)
	if path == "" {
		return
	}
	b, err := json.Marshal(appUpdateCache{CheckedAt: time.Now(), Release: release, Update: u})
	if err != nil {
		return
	}
	if os.MkdirAll(filepath.Dir(path), 0o755) == nil {
		tmp := path + ".tmp"
		if os.WriteFile(tmp, b, 0o644) == nil {
			os.Rename(tmp, path)
		}
	}
}

// releasePages is an app's .buildarg pages that list versions.
func releasePages(a App) []Page {
	if !a.HasWizard {
		return nil
	}
	pages, err := LoadPages(a.WizardDir)
	if err != nil {
		return nil
	}
	var out []Page
	for _, p := range pages {
		if p.Type == "buildarg" && (p.ReleasesRepo != "" || p.ItemsCmd != "") {
			out = append(out, p)
		}
	}
	return out
}

// checkable reports whether an app can have an update state at all.
func checkable(a App) bool {
	return a.Record != nil && a.Record.Release != "" && len(releasePages(a)) > 0
}

// checkAppUpdates starts a check for every app that can have one. Each runs as
// its own command, so a slow app holds up only its own row.
func checkAppUpdates(apps []App, force bool) tea.Cmd {
	var cmds []tea.Cmd
	for _, a := range apps {
		if checkable(a) {
			cmds = append(cmds, checkAppUpdate(a, force))
		}
	}
	return tea.Batch(cmds...)
}

func checkAppUpdate(a App, force bool) tea.Cmd {
	return func() tea.Msg {
		return appUpdateMsg{app: a.Name, upd: resolveAppUpdate(a, force)}
	}
}

// resolveAppUpdate is one app's check, from the cache when it is fresh.
func resolveAppUpdate(a App, force bool) appUpdate {
	release := a.Record.Release
	if !force {
		if u, ok := readAppUpdateCache(a.Name, release); ok {
			return u
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), appUpdateTimeout)
	defer cancel()

	var pages []pageItems
	var firstErr error
	for _, p := range releasePages(a) {
		items, err := versionItems(ctx, p)
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		pages = append(pages, pageItems{Page: p, Items: items})
	}
	u, pi := track(release, pages)
	if u.State == updUnknown && firstErr != nil {
		// Offline or rate-limited: say so, and do not cache it, so the next
		// launch tries again.
		u.Err = firstErr.Error()
		return u
	}

	// An items-cmd page has bare values; its notes are fetched only now, and
	// only for the releases the panel will show.
	if pi >= 0 && pages[pi].Page.ReleasesRepo == "" && pages[pi].Page.NotesRepo != "" {
		want := append([]releaseItem{}, u.Newer...)
		if u.Current != nil {
			want = append(want, *u.Current)
		}
		items := make([]Item, len(want))
		for i, r := range want {
			items[i] = Item{Name: r.Name}
		}
		attachNotes(ctx, pages[pi].Page, items)
		for i := range u.Newer {
			u.Newer[i] = toReleaseItem(items[i])
		}
		if u.Current != nil {
			c := toReleaseItem(items[len(items)-1])
			u.Current = &c
		}
	}
	writeAppUpdateCache(a.Name, release, u)
	return u
}

// versionItems is a page's version list for the check. A releases| page's one
// API call already carries every release's notes; an items-cmd page's values
// are listed without them (attachNotes would cost a request per missing tag,
// for every version the picker offers rather than the few that matter here).
func versionItems(ctx context.Context, p Page) ([]Item, error) {
	if p.ReleasesRepo != "" {
		return buildArgItems(ctx, p)
	}
	out, err := hostCommandContext(ctx, "bash", "-c", p.ItemsCmd).Output()
	if err != nil {
		return nil, err
	}
	var items []Item
	for _, l := range strings.Split(string(out), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			items = append(items, Item{Name: l})
		}
	}
	return items, nil
}
