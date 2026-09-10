package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// releaseServer stands in for api.github.com, so the release tests never touch
// the network — and never spend the caller's 60-per-hour anonymous rate limit.
func releaseServer(t *testing.T, body string) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, "/releases") {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)

	old := ghAPIBase
	ghAPIBase = srv.URL
	t.Cleanup(func() { ghAPIBase = old })
	return srv.URL
}

const twoReleases = `[
 {"tag_name":"v1.0.5","name":"Release v1.0.5","body":"## New\n- a thing","published_at":"2026-09-10T10:00:00Z"},
 {"tag_name":"v1.0.4","name":"Faster inference","body":"older notes","prerelease":true,"published_at":"2026-09-02T10:00:00Z"},
 {"tag_name":"v1.0.3-draft","name":"","body":"unpublished","draft":true}
]`

// The tag is the value the build gets, the body is the notes panel, and a draft
// is not installable by anyone who can see it here, so it is not offered.
func TestReleaseItemsFromAPI(t *testing.T) {
	releaseServer(t, twoReleases)

	rels, err := fetchReleases(context.Background(), "owner/repo", 10)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	items := releaseItems(rels)
	if len(items) != 2 {
		t.Fatalf("got %d items, want 2 (the draft must be dropped)", len(items))
	}
	if items[0].Name != "v1.0.5" || !strings.Contains(items[0].Notes, "- a thing") {
		t.Errorf("first item = %+v", items[0])
	}
	if !strings.Contains(items[0].Desc, "2026-09-10") {
		t.Errorf("Desc = %q, want the publish date", items[0].Desc)
	}
	if !strings.Contains(items[1].Desc, "pre-release") {
		t.Errorf("prerelease not marked: %q", items[1].Desc)
	}
	// "Release v1.0.5" beside the tag v1.0.5 is noise; a real title is not.
	if items[0].NotesTitle != "" {
		t.Errorf("NotesTitle = %q, want the tag echo dropped", items[0].NotesTitle)
	}
	if items[1].NotesTitle != "Faster inference" {
		t.Errorf("NotesTitle = %q, want the real title kept", items[1].NotesTitle)
	}
}

func TestReleaseTitleDropsTagEchoes(t *testing.T) {
	drop := []string{"v1.0.5", "1.0.5", "Release v1.0.5", "Release 1.0.5", "v1.0.5 stable", ""}
	for _, name := range drop {
		if got := releaseTitle(ghRelease{TagName: "v1.0.5", Name: name}); got != "" {
			t.Errorf("releaseTitle(%q) = %q, want dropped", name, got)
		}
	}
	// A tag with a train prefix is routinely titled with the bare version.
	if got := releaseTitle(ghRelease{TagName: "rust-v0.154.0", Name: "0.154.0"}); got != "" {
		t.Errorf("releaseTitle(%q) = %q, want dropped", "0.154.0", got)
	}
	if got := releaseTitle(ghRelease{TagName: "v1.0.5", Name: "Hy-MT2 support"}); got != "Hy-MT2 support" {
		t.Errorf("releaseTitle kept = %q", got)
	}
}

// A releases| page needs no items-cmd, and any extra| values are offered after
// the real releases — comfyui's "master" branch is not a release and has no
// notes, but it is still installable.
func TestBuildArgItemsFromReleasesWithExtras(t *testing.T) {
	releaseServer(t, twoReleases)

	items, err := buildArgItems(context.Background(), Page{
		Type: "buildarg", ArgName: "REF", ReleasesRepo: "owner/repo", Extra: []string{"master"},
	})
	if err != nil {
		t.Fatalf("items: %v", err)
	}
	if len(items) != 3 || items[2].Name != "master" {
		t.Fatalf("items = %+v, want the extra last", items)
	}
	if items[2].Notes != "" {
		t.Errorf("the extra value invented notes: %q", items[2].Notes)
	}
}

// An items-cmd list keeps its own values and ordering; notes-repo only fills in
// the notes, matching each value through the page's tag template.
func TestAttachNotesMatchesTemplateAndLatest(t *testing.T) {
	releaseServer(t, `[
	 {"tag_name":"rust-v0.50.0","name":"","body":"newest notes","published_at":"2026-09-10T10:00:00Z"},
	 {"tag_name":"rust-v0.49.0","name":"","body":"older notes","published_at":"2026-09-01T10:00:00Z"}
	]`)

	items := []Item{{Name: "latest"}, {Name: "0.50.0"}, {Name: "0.1.0"}}
	attachNotes(context.Background(), Page{NotesRepo: "openai/codex", NotesTag: "rust-v%s"}, items)

	if items[1].Notes != "newest notes" {
		t.Errorf("templated match failed: %+v", items[1])
	}
	// "latest" is not a tag: it resolves to the newest release, and says so.
	if items[0].Notes != "newest notes" || !strings.Contains(items[0].NotesTitle, "rust-v0.50.0") {
		t.Errorf("latest = %+v, want the newest release's notes and tag", items[0])
	}
	// A value with no release keeps an empty body rather than borrowing one.
	if items[2].Notes != "" {
		t.Errorf("unmatched value got notes: %+v", items[2])
	}
}

// The notes are a nicety layered onto a list that already works: a failing
// lookup must cost the notes only, never the versions themselves.
func TestAttachNotesFailureKeepsItems(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "rate limited", http.StatusForbidden)
	}))
	defer srv.Close()
	old := ghAPIBase
	ghAPIBase = srv.URL
	defer func() { ghAPIBase = old }()

	items := []Item{{Name: "b1234"}}
	attachNotes(context.Background(), Page{NotesRepo: "ggml-org/llama.cpp"}, items)
	if len(items) != 1 || items[0].Name != "b1234" || items[0].Notes != "" {
		t.Errorf("items = %+v", items)
	}
}

// A repo that ships more than one thing interleaves its trains: "latest" must
// resolve within the train the page's template names, never to whatever was
// published most recently.
func TestLatestRespectsTheTagTemplate(t *testing.T) {
	releaseServer(t, `[
	 {"tag_name":"python-v0.154.0","body":"sdk notes"},
	 {"tag_name":"rust-v0.153.0","body":"cli notes"}
	]`)

	items := []Item{{Name: "latest"}}
	attachNotes(context.Background(), Page{NotesRepo: "openai/codex", NotesTag: "rust-v%s"}, items)
	if items[0].Notes != "cli notes" || !strings.Contains(items[0].NotesTitle, "rust-v0.153.0") {
		t.Errorf("latest = %+v, want the newest rust-v release", items[0])
	}
}

func TestMatchesTemplate(t *testing.T) {
	cases := []struct {
		template, tag string
		want          bool
	}{
		{"rust-v%s", "rust-v0.50.0", true},
		{"rust-v%s", "python-v0.50.0", false},
		{"rust-v%s", "rust-v", false},
		{"%s", "b1234", true},
		{"", "anything", true},
	}
	for _, c := range cases {
		if got := matchesTemplate(c.template, c.tag); got != c.want {
			t.Errorf("matchesTemplate(%q, %q) = %v, want %v", c.template, c.tag, got, c.want)
		}
	}
}
