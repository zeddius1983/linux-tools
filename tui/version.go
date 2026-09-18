package main

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
)

// The installed version, and whether a newer one has been published.
//
// version is stamped at package time with -ldflags "-X main.version=...". A
// dashboard built from a checkout keeps "dev", which is exactly what should be
// shown there: a checkout's version is its git state, not a release.
var version = "dev"

const (
	// updateRepo is the repo whose releases feed the check. Kept here rather
	// than taken from a flag: a dashboard pointed at someone else's releases
	// would be a strange thing to allow by accident.
	updateRepo = "zeddius1983/linux-tools"
	// updateCheckEvery is how stale a cached answer may be. The check costs one
	// redirect, but it happens on every dashboard launch, and a new release
	// lands weekly at most — a day is already more often than it can matter.
	updateCheckEvery = 24 * time.Hour
	// updateCheckTimeout keeps a slow or captive network from being noticeable:
	// the check runs in the background and its result simply never arrives.
	updateCheckTimeout = 3 * time.Second
)

// updateMsg carries the newest published tag back to the event loop.
type updateMsg struct{ latest string }

type updateCache struct {
	CheckedAt time.Time `json:"checked_at"`
	Latest    string    `json:"latest"`
}

func updateCachePath() string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return ""
		}
		base = filepath.Join(home, ".cache")
	}
	return filepath.Join(base, "linux-tools", "update-check")
}

// latestTagURL is the release page whose redirect names the newest tag.
// Overridden by tests.
var latestTagURL = "https://github.com/" + updateRepo + "/releases/latest"

// fetchLatestTag resolves the newest tag without an API call: /releases/latest
// redirects to /releases/tag/<tag>, so the final URL is the answer. The API
// would answer it too, but it rate-limits unauthenticated callers by IP, and a
// check that runs on launch is exactly the wrong thing to have rate-limited.
func fetchLatestTag(ctx context.Context) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, latestTagURL, nil)
	if err != nil {
		return "", err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	final := resp.Request.URL.String()
	idx := strings.LastIndex(final, "/releases/tag/")
	if idx < 0 {
		return "", nil
	}
	return final[idx+len("/releases/tag/"):], nil
}

// checkUpdate answers from the cache when it is fresh, and otherwise asks
// GitHub and writes the answer back. Every failure is silent: no network, a
// captive portal, an unreadable cache, a repo with no releases yet — all of
// them end with no message, and the footer simply shows the installed version.
func checkUpdate() tea.Cmd {
	return func() tea.Msg {
		path := updateCachePath()

		if data, err := os.ReadFile(path); err == nil {
			var c updateCache
			if json.Unmarshal(data, &c) == nil && time.Since(c.CheckedAt) < updateCheckEvery {
				return updateMsg{latest: c.Latest}
			}
		}

		ctx, cancel := context.WithTimeout(context.Background(), updateCheckTimeout)
		defer cancel()
		tag, err := fetchLatestTag(ctx)
		if err != nil || tag == "" {
			return nil
		}

		if path != "" {
			if err := os.MkdirAll(filepath.Dir(path), 0o755); err == nil {
				if data, err := json.Marshal(updateCache{CheckedAt: time.Now(), Latest: tag}); err == nil {
					_ = os.WriteFile(path, data, 0o644)
				}
			}
		}
		return updateMsg{latest: tag}
	}
}

// newerVersion reports whether latest is a later release than installed.
//
// Both are CalVer (YYYY.MM.N, optionally v-prefixed), compared field by field
// as numbers so 2026.09.10 sorts after 2026.09.9 — which a string compare gets
// wrong. Anything that does not parse (a "dev" build, a tag scheme that is not
// ours) reports false: an update hint nobody can act on is worse than none.
func newerVersion(installed, latest string) bool {
	a, okA := parseCalVer(installed)
	b, okB := parseCalVer(latest)
	if !okA || !okB {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return b[i] > a[i]
		}
	}
	return false
}

func parseCalVer(s string) ([3]int, bool) {
	var out [3]int
	s = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(s), "v"))
	parts := strings.Split(s, ".")
	if len(parts) != 3 {
		return out, false
	}
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil {
			return out, false
		}
		out[i] = n
	}
	return out, true
}

// versionLabel is what the footer shows on the right: the installed version,
// and the newer one when there is one.
func (m *model) versionLabel() string {
	if version == "dev" {
		return ""
	}
	cur := "v" + strings.TrimPrefix(version, "v")
	if m.latest != "" && newerVersion(version, m.latest) {
		return styWarn.Render(cur + " → " + m.latest)
	}
	return styDesc.Render(cur)
}
