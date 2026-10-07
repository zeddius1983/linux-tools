package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
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
	var rels []ghRelease
	if err := ghGet(ctx, fmt.Sprintf("%s/repos/%s/releases?per_page=%d", ghAPIBase, repo, limit), &rels); err != nil {
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

// fetchRelease looks up a single release by its tag.
func fetchRelease(ctx context.Context, repo, tag string) (ghRelease, error) {
	var r ghRelease
	err := ghGet(ctx, fmt.Sprintf("%s/repos/%s/releases/tags/%s", ghAPIBase, repo, tag), &r)
	return r, err
}

// ghGet decodes one GitHub API response into v.
func ghGet(ctx context.Context, url string, v any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
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
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("github: %s", resp.Status)
	}
	return json.NewDecoder(resp.Body).Decode(v)
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
func releaseItems(rels []ghRelease, repo string) []Item {
	items := make([]Item, 0, len(rels))
	for _, r := range rels {
		items = append(items, Item{
			Name:       r.TagName,
			Desc:       releaseDesc(r),
			Notes:      r.Body,
			NotesTitle: releaseTitle(r, repo),
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
// "1.0.5", "openclaw 2026.9.4" — which next to the tag itself says nothing, so
// those are dropped and only a real title survives.
func releaseTitle(r ghRelease, repo string) string {
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
	rest = strings.ToLower(strings.Trim(rest, " \t-—–:·.,()[]vV"))
	switch rest {
	case "", "release", "version", "stable":
		return ""
	}
	// The project's own name is the same kind of nothing: the list is one app's
	// versions, so "openclaw 2026.9.4" beside the tag 2026.9.4 only repeats
	// which app is being installed. Compared loosely, because a repo called
	// llama.cpp titles releases "llama.cpp b1234".
	if r, n := squashName(rest), squashName(repoName(repo)); n != "" && r == n {
		return ""
	}
	return name
}

// repoName is the name half of "owner/repo".
func repoName(repo string) string {
	if _, name, ok := strings.Cut(repo, "/"); ok {
		return name
	}
	return repo
}

// squashName reduces a name to its letters and digits, so "llama.cpp" and
// "llama-cpp" compare equal.
func squashName(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		}
	}
	return b.String()
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
	// resolved to so the two are never confused. Other aliases ("nightly") work
	// the same way within their own tag template.
	alias := func(name string) (string, bool) {
		name = strings.ToLower(name)
		if t, ok := p.Aliases[name]; ok {
			return t, true
		}
		return p.NotesTag, name == "latest"
	}

	// Tags the list is too shallow to reach are looked up one by one. llama.cpp
	// publishes a b#### release for nearly every commit, so its vX.Y.Z releases
	// sit hundreds of entries apart and only the newest falls inside the list.
	// It costs a request per miss, which is why the bulk list comes first.
	var (
		mu sync.Mutex
		wg sync.WaitGroup
	)
	for _, it := range items {
		tag := notesTag(p.NotesTag, it.Name)
		if _, ok := byTag[tag]; ok {
			continue
		}
		if _, ok := alias(it.Name); ok {
			continue
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			if r, err := fetchRelease(ctx, p.NotesRepo, tag); err == nil && !r.Draft && r.TagName == tag {
				mu.Lock()
				byTag[tag] = r
				mu.Unlock()
			}
		}()
	}
	wg.Wait()

	// The listed tags' releases, in the page's order — newest first, as every
	// items-cmd prints them. An alias falls back to these when the bulk list
	// holds nothing of its shape: llama.cpp cuts ~25 b#### releases a day, so a
	// couple of days after a vX.Y.Z release the newest 50 are all builds, and
	// "latest" would otherwise lose its notes while v0.6.0 sits right below it.
	var listed []ghRelease
	for _, it := range items {
		if _, ok := alias(it.Name); ok {
			continue
		}
		if r, ok := byTag[notesTag(p.NotesTag, it.Name)]; ok {
			listed = append(listed, r)
		}
	}

	for i := range items {
		r, ok := byTag[notesTag(p.NotesTag, items[i].Name)]
		if ok {
			items[i].Notes, items[i].NotesTitle = r.Body, releaseTitle(r, p.NotesRepo)
			if items[i].Desc == "" {
				items[i].Desc = releaseDesc(r)
			}
			continue
		}
		tmpl, isAlias := alias(items[i].Name)
		if !isAlias {
			continue
		}
		newest := newestStable(rels, tmpl)
		if newest == nil {
			newest = newestStable(listed, tmpl)
		}
		if newest != nil {
			items[i].Notes = newest.Body
			items[i].NotesTitle = strings.TrimSpace(newest.TagName + " " + releaseTitle(*newest, p.NotesRepo))
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
