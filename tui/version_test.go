package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNewerVersion(t *testing.T) {
	tests := []struct {
		installed, latest string
		want              bool
	}{
		{"2026.09.1", "v2026.09.2", true},
		{"2026.09.1", "v2026.10.0", true},
		{"2026.12.1", "v2027.01.0", true},
		{"2026.09.1", "v2026.09.1", false},
		{"2026.09.2", "v2026.09.1", false},
		{"v2026.09.1", "v2026.09.2", true},

		// A string compare gets this one wrong, which is the whole reason the
		// fields are parsed as numbers.
		{"2026.09.9", "v2026.09.10", true},
		{"2026.09.10", "v2026.09.9", false},

		// Nothing actionable: a checkout build, or a tag that is not ours.
		{"dev", "v2026.09.1", false},
		{"2026.09.1", "", false},
		{"2026.09.1", "nightly", false},
		{"2026.09", "v2026.09.1", false},
	}
	for _, tc := range tests {
		if got := newerVersion(tc.installed, tc.latest); got != tc.want {
			t.Errorf("newerVersion(%q, %q) = %v, want %v", tc.installed, tc.latest, got, tc.want)
		}
	}
}

// The tag comes out of the redirect target, not a response body: that is what
// keeps the check off the rate-limited API.
func TestFetchLatestTag(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/releases/latest" {
			http.Redirect(w, r, "/releases/tag/v2026.09.1", http.StatusFound)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	old := latestTagURL
	latestTagURL = srv.URL + "/releases/latest"
	defer func() { latestTagURL = old }()

	tag, err := fetchLatestTag(context.Background())
	if err != nil {
		t.Fatalf("fetchLatestTag: %v", err)
	}
	if tag != "v2026.09.1" {
		t.Errorf("tag = %q, want v2026.09.1", tag)
	}
}

// A repo with no releases does not redirect to a tag. That is not an error and
// must not be reported as one — it just means there is nothing to offer.
func TestFetchLatestTagNoReleases(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	old := latestTagURL
	latestTagURL = srv.URL + "/releases/latest"
	defer func() { latestTagURL = old }()

	tag, err := fetchLatestTag(context.Background())
	if err != nil {
		t.Fatalf("fetchLatestTag: %v", err)
	}
	if tag != "" {
		t.Errorf("tag = %q, want empty", tag)
	}
}

func TestVersionLabel(t *testing.T) {
	old := version
	defer func() { version = old }()

	m := newModel([]App{{Name: "x", Category: "Other"}}, "apps", "tools", false)

	// A checkout build has no release version to show.
	version = "dev"
	if got := m.versionLabel(); got != "" {
		t.Errorf("dev build label = %q, want empty", got)
	}

	version = "2026.09.1"
	if got := m.versionLabel(); got == "" {
		t.Error("release build shows no version")
	}

	// An older "latest" must not produce an update hint.
	m.latest = "v2026.08.1"
	plain := m.versionLabel()
	m.latest = "v2026.10.0"
	hinted := m.versionLabel()
	if plain == hinted {
		t.Error("a newer release does not change the footer label")
	}
	if !strings.Contains(hinted, "v2026.10.0") {
		t.Errorf("update label %q does not name the new version", hinted)
	}
}
