package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"
)

// GitHub releases for .buildarg wizard pages.
//
// A page can name a repo instead of writing its own items-cmd, and then the
// list of installable versions *and* each version's release notes arrive in a
// single API call. Doing it here rather than in the page's shell command is
// what makes the notes possible at all: the JSON body of a release is
// multi-line markdown, which the one-value-per-line items-cmd protocol has no
// way to carry, and which curl|grep|sed has no honest way to unescape.

// ghAPIBase is the API root, overridden by tests.
var ghAPIBase = "https://api.github.com"

const (
	// defaultReleaseLimit matches the per_page=10 the hand-written items-cmds
	// used: ten versions is already more choice than a version picker needs.
	defaultReleaseLimit = 10
	// defaultNotesLimit is deliberately deeper. A notes-repo lookup has to find
	// the release behind an items-cmd value, and that list is filtered (codex
	// offers only stable rust-v tags) while the releases feed is not: repos
	// that publish several trains from one repo — an SDK, a CLI, nightlies —
	// interleave them, so the newest ten releases can contain barely any of the
	// ones being offered. It is still a single request.
	defaultNotesLimit = 50
)

type ghRelease struct {
	TagName     string    `json:"tag_name"`
	Name        string    `json:"name"`
	Body        string    `json:"body"`
	Draft       bool      `json:"draft"`
	Prerelease  bool      `json:"prerelease"`
	PublishedAt time.Time `json:"published_at"`
}

// fetchReleases lists a repo's releases, newest first, as the API returns them.
//
// Drafts are dropped: they are only ever visible to a token that can see them,
// and they are not installable by anyone else.
func fetchReleases(ctx context.Context, repo string, limit int) ([]ghRelease, error) {
	if repo == "" {
		return nil, fmt.Errorf("no repo")
	}
	if limit <= 0 {
		limit = defaultReleaseLimit
	}
	url := fmt.Sprintf("%s/repos/%s/releases?per_page=%d", ghAPIBase, repo, limit)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "linux-tools-tui")
	// Unauthenticated calls are limited to 60/hour per IP, which a few wizard
	// openings can exhaust on a shared address. A token in the environment is
	// used when there is one; there is deliberately no prompt for one.
	if tok := githubToken(); tok != "" {
		req.Header.Set("Authorization", "Bearer "+tok)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("github: %s", resp.Status)
	}

	var rels []ghRelease
	if err := json.NewDecoder(resp.Body).Decode(&rels); err != nil {
		return nil, err
	}
	out := rels[:0]
	for _, r := range rels {
		if !r.Draft && r.TagName != "" {
			out = append(out, r)
		}
	}
	return out, nil
}

func githubToken() string {
	for _, k := range []string{"GITHUB_TOKEN", "GH_TOKEN"} {
		if v := strings.TrimSpace(os.Getenv(k)); v != "" {
			return v
		}
	}
	return ""
}

// releaseItems turns releases into wizard items: the tag is the value handed to
// the build, the date and pre-release marker are the list's description column,
// and the notes fill the panel beside it.
func releaseItems(rels []ghRelease) []Item {
	items := make([]Item, 0, len(rels))
	for _, r := range rels {
		items = append(items, Item{
			Name:       r.TagName,
			Desc:       releaseDesc(r),
			Notes:      r.Body,
			NotesTitle: releaseTitle(r),
		})
	}
	return items
}

func releaseDesc(r ghRelease) string {
	var parts []string
	if !r.PublishedAt.IsZero() {
		parts = append(parts, r.PublishedAt.Local().Format("2006-01-02"))
	}
	if r.Prerelease {
		parts = append(parts, "pre-release")
	}
	return strings.Join(parts, " · ")
}

// releaseTitle is the heading shown beside the tag, above the notes.
//
// Most projects title a release after its own tag — "Release v1.0.5", "v1.0.5",
// "1.0.5" — which next to the tag itself says nothing, so those are dropped and
// only a real title survives.
func releaseTitle(r ghRelease) string {
	name := strings.TrimSpace(r.Name)
	if name == "" || name == r.TagName {
		return ""
	}
	// Take out the version the tag already shows — as the tag is written, and
	// as the bare version inside it, since a "rust-v0.154.0" tag is routinely
	// titled just "0.154.0" — and see whether anything but a word like
	// "Release" is left.
	rest := strings.ReplaceAll(name, r.TagName, "")
	if core := versionCore.FindString(r.TagName); core != "" {
		rest = strings.ReplaceAll(rest, core, "")
	}
	switch strings.ToLower(strings.Trim(rest, " \t-—–:·.,()[]vV")) {
	case "", "release", "version", "stable":
		return ""
	}
	return name
}

// versionCore is the version inside a tag: the digits and everything that
// belongs to them, with any prefix ("v", "rust-v", "b") left behind.
var versionCore = regexp.MustCompile(`[0-9][0-9A-Za-z.+\-]*`)

// attachNotes fills in notes for items that came from an items-cmd, by matching
// each value against the tags of the page's notes-repo.
//
// It is best-effort by design: the items are already on screen and installable,
// so a rate-limited or offline lookup must cost the notes only, never the list.
func attachNotes(ctx context.Context, p Page, items []Item) {
	limit := p.NotesLimit
	if limit <= 0 {
		limit = defaultNotesLimit
	}
	rels, err := fetchReleases(ctx, p.NotesRepo, limit)
	if err != nil || len(rels) == 0 {
		return
	}
	byTag := make(map[string]ghRelease, len(rels))
	for _, r := range rels {
		byTag[r.TagName] = r
	}
	// "latest" is not a tag: every installer that offers it means "whatever is
	// newest", so it shows the newest release's notes, labelled with the tag it
	// resolved to so the two are never confused.
	newest := newestStable(rels, p.NotesTag)

	for i := range items {
		r, ok := byTag[notesTag(p.NotesTag, items[i].Name)]
		switch {
		case ok:
			items[i].Notes, items[i].NotesTitle = r.Body, releaseTitle(r)
			if items[i].Desc == "" {
				items[i].Desc = releaseDesc(r)
			}
		case strings.EqualFold(items[i].Name, "latest") && newest != nil:
			items[i].Notes = newest.Body
			items[i].NotesTitle = strings.TrimSpace(newest.TagName + " " + releaseTitle(*newest))
			if items[i].Desc == "" {
				items[i].Desc = releaseDesc(*newest)
			}
		}
	}
}

// notesTag renders an item value into the repo's tag form. A page whose values
// are already tags needs no template; codex's are bare versions of a `rust-v`
// tag, hence "rust-v%s".
func notesTag(template, value string) string {
	if template == "" {
		return value
	}
	return strings.ReplaceAll(template, "%s", value)
}

// newestStable is the release "latest" means, among those the page's tag
// template can name.
//
// The template is what makes this correct on a repo that ships more than one
// thing: openai/codex releases a Python SDK from the same repo, and its
// python-v tags are usually the newest releases there — but a wizard offering
// rust-v versions must never show one of those as what "latest" installs.
func newestStable(rels []ghRelease, template string) *ghRelease {
	var first *ghRelease
	for i := range rels {
		if !matchesTemplate(template, rels[i].TagName) {
			continue
		}
		if first == nil {
			first = &rels[i]
		}
		if !rels[i].Prerelease {
			return &rels[i]
		}
	}
	return first
}

// matchesTemplate reports whether a tag has the shape a notes-repo template
// produces: "rust-v%s" matches rust-v0.50.0 and nothing else. An empty template
// matches everything, which is the no-template case.
func matchesTemplate(template, tag string) bool {
	prefix, suffix, found := strings.Cut(template, "%s")
	if !found {
		return template == "" || template == tag
	}
	return len(tag) > len(prefix)+len(suffix) &&
		strings.HasPrefix(tag, prefix) && strings.HasSuffix(tag, suffix)
}
