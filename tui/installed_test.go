package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCompareVersions(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"v1.4.0", "v1.3.9", 1},
		{"v1.10.0", "v1.9.0", 1}, // numeric, not lexical
		{"0.166.0", "0.166.0", 0},
		{"v0.2.3.1", "v0.2.3", 1}, // strata's four-part tags
		{"v2.2.0", "v1.19.5", 1},  // published later, still older
		{"b12022", "b12008", 1},
		{"2026.10.9", "2026.9.36", 1}, // openclaw's interleaved trains
		{"v0.10.1rc1", "v0.10.1", -1}, // a release outranks its own rc
		{"v0.10.1rc2", "v0.10.1rc1", 1},
		{"0.166.0-alpha.6", "0.165.0", 1},
	}
	for _, c := range cases {
		if got := compareVersions(parseVersion(c.a), parseVersion(c.b)); got != c.want {
			t.Errorf("compare(%s, %s) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

func TestParseVersion(t *testing.T) {
	v := parseVersion("rust-v0.166.0-alpha.6")
	if v.prefix != "rust-v" || len(v.nums) != 3 || v.nums[1] != 166 || v.suffix != "-alpha.6" {
		t.Errorf("got %+v", v)
	}
	if v := parseVersion("0.32.1.dev45"); len(v.nums) != 3 || v.suffix != ".dev45" {
		t.Errorf("dev suffix: got %+v", v)
	}
	if v := parseVersion("master"); len(v.nums) != 0 {
		t.Errorf("master has no numbers: got %+v", v)
	}
}

func items(names ...string) []Item {
	out := make([]Item, len(names))
	for i, n := range names {
		out[i] = Item{Name: n}
	}
	return out
}

func names(rs []releaseItem) []string {
	var out []string
	for _, r := range rs {
		out = append(out, r.Name)
	}
	return out
}

func eq(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestTrackUpdateAvailable(t *testing.T) {
	// opencode's feed is in publish order: v1.19.5 shipped after v2.2.0.
	p := pageItems{Page: Page{ReleasesRepo: "x/y"}, Items: items("v2.2.5", "v2.2.4", "v1.19.5", "v2.2.0")}
	u, pi := track("v2.2.0", []pageItems{p})
	if u.State != updAvailable || u.Latest != "v2.2.5" || pi != 0 {
		t.Fatalf("got %+v page %d", u, pi)
	}
	if !eq(names(u.Newer), []string{"v2.2.5", "v2.2.4"}) {
		t.Errorf("newer = %v (v1.19.5 is not newer than v2.2.0)", names(u.Newer))
	}
	if u.Current == nil || u.Current.Name != "v2.2.0" {
		t.Errorf("current = %+v", u.Current)
	}
}

func TestTrackUpToDate(t *testing.T) {
	p := pageItems{Page: Page{Extra: []string{"master"}}, Items: items("v0.43.0", "v0.42.1", "master")}
	u, _ := track("v0.43.0", []pageItems{p})
	if u.State != updCurrent || len(u.Newer) != 0 || u.Current == nil {
		t.Fatalf("got %+v", u)
	}
}

func TestTrackBranch(t *testing.T) {
	p := pageItems{Page: Page{Extra: []string{"master"}}, Items: items("v0.43.0", "master")}
	if u, _ := track("master", []pageItems{p}); u.State != updBranch {
		t.Errorf("master: got %+v", u)
	}
	vllm := pageItems{Page: Page{Extra: []string{"latest", "nightly"}}, Items: items("v0.32.0", "latest", "nightly")}
	if u, _ := track("nightly", []pageItems{vllm}); u.State != updBranch {
		t.Errorf("nightly: got %+v", u)
	}
}

// llama.cpp: two pages share LLAMA_REF, and the installed tag's prefix says
// which one it came from.
func TestTrackPicksPageByPrefix(t *testing.T) {
	rel := pageItems{
		Page:  Page{Aliases: map[string]string{"latest": "v%s"}},
		Items: items("latest", "v4.1.0", "v4.0.1"),
	}
	build := pageItems{
		Page:  Page{Aliases: map[string]string{"nightly": "b%s"}},
		Items: []Item{{Name: "nightly"}, {Name: "b12022", Prerelease: true}, {Name: "b12008", Prerelease: true}},
	}
	u, pi := track("v4.0.1", []pageItems{rel, build})
	if pi != 0 || u.Latest != "v4.1.0" || !eq(names(u.Newer), []string{"v4.1.0"}) {
		t.Errorf("release install: got %+v page %d", u, pi)
	}
	// Every build is a GitHub pre-release; with nothing else on the track
	// they still count.
	u, pi = track("b12008", []pageItems{rel, build})
	if pi != 1 || u.State != updAvailable || u.Latest != "b12022" {
		t.Errorf("build install: got %+v page %d", u, pi)
	}
}

func TestTrackPrereleases(t *testing.T) {
	p := pageItems{Page: Page{ReleasesRepo: "x/y"}, Items: []Item{
		{Name: "v0.11.0rc1", Prerelease: true},
		{Name: "v0.10.1"},
		{Name: "v0.10.1rc1", Prerelease: true},
	}}
	// A stable install is not offered a release candidate.
	if u, _ := track("v0.10.1", []pageItems{p}); u.State != updCurrent {
		t.Errorf("stable: got %+v", u)
	}
	// An rc install is.
	if u, _ := track("v0.10.1rc1", []pageItems{p}); u.State != updAvailable || u.Latest != "v0.11.0rc1" {
		t.Errorf("rc: got %+v", u)
	}
}

func TestTrackUnknown(t *testing.T) {
	p := pageItems{Page: Page{}, Items: items("v1.0.0")}
	if u, _ := track("", []pageItems{p}); u.State != updUnknown {
		t.Errorf("no release: got %+v", u)
	}
	if u, _ := track("1.0.0", []pageItems{p}); u.State != updUnknown {
		t.Errorf("prefix mismatch: got %+v", u)
	}
}

func TestLoadInstallRecord(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_STATE_HOME", dir)
	rec := filepath.Join(dir, "linux-tools", "installed")
	if err := os.MkdirAll(rec, 0o755); err != nil {
		t.Fatal(err)
	}
	body := "RELEASE=v1.2.0\nARGS=PI_RELEASE=v1.2.0\nVARIANT=\nIMAGE_ID=c6752e26b706503a97a9\nBUILT_AT=2026-10-31T20:28:04Z\n"
	if err := os.WriteFile(filepath.Join(rec, "pi"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	r := loadInstallRecord("pi", "c6752e26b706")
	if r == nil || r.Release != "v1.2.0" || r.Args != "PI_RELEASE=v1.2.0" || r.BuiltAt.IsZero() {
		t.Fatalf("got %+v", r)
	}
	if loadInstallRecord("pi", "sha256:c6752e26b706") == nil {
		t.Error("a sha256: prefix should not matter")
	}
	if loadInstallRecord("pi", "0000aaaa1111") != nil {
		t.Error("a record for another image must be ignored")
	}
	if loadInstallRecord("nope", "c6752e26b706") != nil {
		t.Error("no record file should be nil")
	}
}
