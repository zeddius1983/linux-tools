package main

import (
	"bufio"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// What an app's build installed, and whether its release picker now offers
// something newer.
//
// The record is written by record_install (lib/commands.sh) after every build:
// a release picker's "latest" is resolved inside the Dockerfile, which writes
// the version it ended up with to /usr/share/linux-tools/release, and the
// backend reads that back while the image is fresh. Apps built before records
// existed simply have none, and show no update state at all — every app is
// rebuilt sooner or later, so there is no attempt to probe old images.

// InstallRecord is one apps' $XDG_STATE_HOME/linux-tools/installed/<app>.
type InstallRecord struct {
	Release string // as the picker writes it: "v1.4.0", "0.166.0", "master"
	Args    string // the build args it was built with, "K=v K=v"
	Variant string // the .runtime selection
	ImageID string // full ID, without "sha256:"
	BuiltAt time.Time
}

func installRecordDir() string {
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return ""
		}
		base = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(base, "linux-tools", "installed")
}

// loadInstallRecord reads an app's record, provided it describes the image
// that is there now. A record for another image — rebuilt outside tools, or
// left behind by a build that failed after the old image was removed — would
// describe something that is not installed, so it is ignored.
func loadInstallRecord(app, imageID string) *InstallRecord {
	dir := installRecordDir()
	if dir == "" {
		return nil
	}
	f, err := os.Open(filepath.Join(dir, app))
	if err != nil {
		return nil
	}
	defer f.Close()
	var r InstallRecord
	s := bufio.NewScanner(f)
	for s.Scan() {
		k, v, ok := strings.Cut(s.Text(), "=")
		if !ok {
			continue
		}
		switch k {
		case "RELEASE":
			r.Release = v
		case "ARGS":
			r.Args = v
		case "VARIANT":
			r.Variant = v
		case "IMAGE_ID":
			r.ImageID = strings.TrimPrefix(v, "sha256:")
		case "BUILT_AT":
			r.BuiltAt, _ = time.Parse(time.RFC3339, v)
		}
	}
	imageID = strings.TrimPrefix(imageID, "sha256:")
	if imageID == "" || r.ImageID == "" || !strings.HasPrefix(r.ImageID, imageID) {
		return nil
	}
	return &r
}

// --- versions ----------------------------------------------------------------

// version is a tag taken apart: "rust-v0.166.0-alpha.6" is prefix "rust-v",
// numbers [0 166 0], suffix "-alpha.6".
type tagVersion struct {
	prefix string
	nums   []int
	suffix string
}

func parseVersion(s string) tagVersion {
	var v tagVersion
	i := strings.IndexFunc(s, isDigit)
	if i < 0 {
		v.prefix = s
		return v
	}
	v.prefix, s = s[:i], s[i:]
	for {
		j := 0
		n := 0
		for j < len(s) && isDigit(rune(s[j])) {
			n = n*10 + int(s[j]-'0')
			j++
		}
		v.nums = append(v.nums, n)
		s = s[j:]
		// A dot carries on only into another number: "0.32.1.dev45" stops
		// before ".dev45", which is the suffix.
		if len(s) >= 2 && s[0] == '.' && isDigit(rune(s[1])) {
			s = s[1:]
			continue
		}
		break
	}
	v.suffix = s
	return v
}

func isDigit(r rune) bool { return r >= '0' && r <= '9' }

// prerelease reports whether the tag carries anything after its numbers —
// "-beta.5", "rc1", "-alpha.6". Build metadata is already stripped by the
// Dockerfiles that have any (vllm's "+rocm723").
func (v tagVersion) prerelease() bool { return v.suffix != "" }

// compareVersions orders two parsed tags by their numbers, missing ones
// counting as zero, then a release above any pre-release of the same numbers,
// then two pre-releases by compareSuffix.
func compareVersions(a, b tagVersion) int {
	for i := 0; i < len(a.nums) || i < len(b.nums); i++ {
		var x, y int
		if i < len(a.nums) {
			x = a.nums[i]
		}
		if i < len(b.nums) {
			y = b.nums[i]
		}
		if x != y {
			if x < y {
				return -1
			}
			return 1
		}
	}
	switch {
	case a.suffix == b.suffix:
		return 0
	case a.suffix == "":
		return 1
	case b.suffix == "":
		return -1
	default:
		return compareSuffix(a.suffix, b.suffix)
	}
}

// compareSuffix orders two pre-release suffixes run by run: digit runs as
// numbers, everything else as text. Compared whole as strings, "rc10" sorts
// below "rc2" and "-alpha.10" below "-alpha.2", which would report an rc2
// install as current while offering an rc10 install a downgrade to rc2.
// When one suffix runs out first, the shorter one is older ("-alpha" <
// "-alpha.1").
func compareSuffix(a, b string) int {
	for a != "" && b != "" {
		ra, restA := nextRun(a)
		rb, restB := nextRun(b)
		da, db := isDigit(rune(ra[0])), isDigit(rune(rb[0]))
		var c int
		switch {
		case da && db:
			c = compareDigits(ra, rb)
		case da != db:
			// A number against text has no natural order; text sorts first
			// so the result is at least deterministic.
			if da {
				c = 1
			} else {
				c = -1
			}
		default:
			c = strings.Compare(ra, rb)
		}
		if c != 0 {
			return c
		}
		a, b = restA, restB
	}
	switch {
	case a == b:
		return 0
	case a == "":
		return -1
	default:
		return 1
	}
}

// nextRun splits off the leading run of digits, or of non-digits.
func nextRun(s string) (run, rest string) {
	digits := isDigit(rune(s[0]))
	i := 1
	for i < len(s) && isDigit(rune(s[i])) == digits {
		i++
	}
	return s[:i], s[i:]
}

// compareDigits compares two digit strings as numbers of any length, without
// converting them: leading zeros dropped, then longer is larger, then text.
func compareDigits(a, b string) int {
	a, b = strings.TrimLeft(a, "0"), strings.TrimLeft(b, "0")
	if len(a) != len(b) {
		if len(a) < len(b) {
			return -1
		}
		return 1
	}
	return strings.Compare(a, b)
}

// --- update state ------------------------------------------------------------

type updateState int

const (
	// updUnknown: nothing to compare — no record, or a release that matches
	// none of the picker's versions.
	updUnknown updateState = iota
	updCurrent
	updAvailable
	// updBranch: the install tracks a moving ref (comfyui's master, vllm's
	// nightly), which has no version to be behind.
	updBranch
	// updChecking: a check is in flight. Never cached.
	updChecking
)

// releaseItem is the part of a wizard Item an update needs, kept separately so
// it can be cached as JSON.
type releaseItem struct {
	Name       string `json:"name"`
	Desc       string `json:"desc,omitempty"`
	Notes      string `json:"notes,omitempty"`
	NotesTitle string `json:"notes_title,omitempty"`
}

func toReleaseItem(it Item) releaseItem {
	return releaseItem{Name: it.Name, Desc: it.Desc, Notes: it.Notes, NotesTitle: it.NotesTitle}
}

// appUpdate is the answer for one app.
type appUpdate struct {
	State     updateState   `json:"state"`
	Installed string        `json:"installed"`
	Latest    string        `json:"latest,omitempty"`
	Newer     []releaseItem `json:"newer,omitempty"` // newest first
	// Current is the installed release's own entry, for its notes when there
	// is nothing newer to show.
	Current *releaseItem `json:"current,omitempty"`
	Err     string       `json:"-"`
}

// pageItems is one .buildarg page with the versions it offers.
type pageItems struct {
	Page  Page
	Items []Item
}

// moving reports whether a value names no version of its own on this page:
// "latest", an alias ("nightly" for the newest b####), or an extra| literal
// ("master").
func (p Page) moving(name string) bool {
	n := strings.ToLower(name)
	if n == "latest" {
		return true
	}
	if _, ok := p.Aliases[n]; ok {
		return true
	}
	for _, e := range p.Extra {
		if strings.EqualFold(e, name) {
			return true
		}
	}
	return false
}

// track is the evaluation proper: which of the picker's versions are the same
// kind as the installed one, and which of those are newer.
//
// "The same kind" is the tag's prefix — the picker's own filtering already
// keeps other products out (codex's alphas, orca's Android builds), so what is
// left to separate is llama.cpp's two pages sharing one build arg: an install
// from the Release page ("v…") is compared with releases, one from the Build
// page ("b…") with builds. Pre-releases count only when the installed version
// is one too, or when there is nothing else on the track (every llama.cpp
// b#### is flagged pre-release on GitHub).
//
// It returns the index of the page the track was found on, for the notes
// lookup that only items-cmd pages need, or -1.
func track(installed string, pages []pageItems) (appUpdate, int) {
	u := appUpdate{State: updUnknown, Installed: installed}
	if installed == "" {
		return u, -1
	}
	for _, p := range pages {
		if p.Page.moving(installed) {
			u.State = updBranch
			return u, -1
		}
	}
	iv := parseVersion(installed)
	if len(iv.nums) == 0 {
		return u, -1
	}

	type cand struct {
		it  Item
		v   tagVersion
		pre bool
	}
	for pi, p := range pages {
		var cands []cand
		seen := map[string]bool{}
		for _, it := range p.Items {
			if p.Page.moving(it.Name) || seen[it.Name] {
				continue
			}
			v := parseVersion(it.Name)
			if len(v.nums) == 0 || v.prefix != iv.prefix {
				continue
			}
			seen[it.Name] = true
			cands = append(cands, cand{it, v, it.Prerelease || v.prerelease()})
		}
		if len(cands) == 0 {
			continue
		}
		if !iv.prerelease() {
			var stable []cand
			for _, c := range cands {
				if !c.pre {
					stable = append(stable, c)
				}
			}
			if len(stable) > 0 {
				cands = stable
			}
		}
		sort.SliceStable(cands, func(i, j int) bool { return compareVersions(cands[i].v, cands[j].v) > 0 })

		u.State = updCurrent
		u.Latest = cands[0].it.Name
		for _, c := range cands {
			switch cmp := compareVersions(c.v, iv); {
			case cmp > 0:
				u.Newer = append(u.Newer, toReleaseItem(c.it))
			case cmp == 0 && u.Current == nil:
				ri := toReleaseItem(c.it)
				u.Current = &ri
			}
		}
		if len(u.Newer) > 0 {
			u.State = updAvailable
		} else {
			// Installed is the newest the picker knows of, or newer still
			// (a pin the shallow list has already scrolled past is the
			// other way round, and lands in Newer).
			u.Latest = installed
		}
		return u, pi
	}
	return u, -1
}
