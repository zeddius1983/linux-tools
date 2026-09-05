package main

import (
	"path/filepath"
	"strings"
	"testing"
)

const appsDir = "../apps"

// Parses the real wizard pages in the repo rather than fixtures, so a drift
// between the page format and this parser fails the test.
func TestParseRealPages(t *testing.T) {
	// Item counts are lower bounds: apps gain wizard entries over time and
	// this test should not have to be edited every time one does.
	cases := []struct {
		app      string
		page     string
		typ      string
		minItems int
	}{
		{"claude-code", "00-statusline", "packages", 1},
		{"dev-toolbox", "00-tools", "packages", 8},
		{"shell-toolbox", "00-tools", "packages", 1},
		{"lmstudio", "00-runtime", "runtime", 2},
		{"fastflowlm", "00-release", "buildarg", 0},
		{"codex-cli", "00-release", "buildarg", 0},
	}

	for _, c := range cases {
		pages, err := LoadPages(filepath.Join(appsDir, c.app, "wizard"))
		if err != nil {
			t.Fatalf("%s: %v", c.app, err)
		}
		var got *Page
		for i := range pages {
			if pages[i].Name == c.page {
				got = &pages[i]
			}
		}
		if got == nil {
			t.Fatalf("%s: page %q not found", c.app, c.page)
		}
		if got.Type != c.typ {
			t.Errorf("%s/%s: type = %q, want %q", c.app, c.page, got.Type, c.typ)
		}
		if got.Title == "" || got.Prompt == "" {
			t.Errorf("%s/%s: empty header", c.app, c.page)
		}
		if len(got.Applicable) == 0 {
			t.Errorf("%s/%s: no applicable actions", c.app, c.page)
		}
		if len(got.Items) < c.minItems {
			t.Errorf("%s/%s: %d items, want at least %d", c.app, c.page, len(got.Items), c.minItems)
		}
	}
}

// Codex's release page must keep "latest" as the preferred choice while also
// discovering stable rust-v tags and passing the answer to the installer arg.
func TestCodexBuildargConfig(t *testing.T) {
	pages, err := LoadPages(filepath.Join(appsDir, "codex-cli", "wizard"))
	if err != nil || len(pages) == 0 {
		t.Fatalf("load: %v", err)
	}
	p := pages[0]
	if p.ArgName != "CODEX_RELEASE" {
		t.Errorf("ArgName = %q, want CODEX_RELEASE", p.ArgName)
	}
	for _, want := range []string{"printf", "latest", "git ls-remote", "rust-v", "sort -V"} {
		if !strings.Contains(p.ItemsCmd, want) {
			t.Errorf("ItemsCmd missing %q: %q", want, p.ItemsCmd)
		}
	}
	if len(p.Items) != 0 {
		t.Errorf("buildarg body should yield no items, got %d", len(p.Items))
	}
}

// .buildarg bodies are config, not items: arg + items-cmd must survive parsing,
// including an items-cmd containing pipes.
func TestBuildargConfig(t *testing.T) {
	pages, err := LoadPages(filepath.Join(appsDir, "fastflowlm", "wizard"))
	if err != nil || len(pages) == 0 {
		t.Fatalf("load: %v", err)
	}
	p := pages[0]
	if p.ArgName != "FLM_REF" {
		t.Errorf("ArgName = %q, want FLM_REF", p.ArgName)
	}
	if !strings.Contains(p.ItemsCmd, "curl") || !strings.Contains(p.ItemsCmd, "|") {
		t.Errorf("ItemsCmd did not survive pipe-splitting: %q", p.ItemsCmd)
	}
	if len(p.Items) != 0 {
		t.Errorf("buildarg body should yield no items, got %d", len(p.Items))
	}
}

// .runtime carries label and value separately; the value is what reaches
// create_flags.<variant>, and it must never be the label.
func TestRuntimeLabelValueSplit(t *testing.T) {
	pages, err := LoadPages(filepath.Join(appsDir, "lmstudio", "wizard"))
	if err != nil || len(pages) == 0 {
		t.Fatalf("load: %v", err)
	}
	p := pages[0]
	want := map[string]string{
		"AMD (ROCm/Vulkan)": "amd",
		"NVIDIA (CUDA)":     "nvidia",
	}
	for _, it := range p.Items {
		if want[it.Name] != it.Payload {
			t.Errorf("item %q: value = %q, want %q", it.Name, it.Payload, want[it.Name])
		}
	}
}

// A .runtime page may carry an 'arg|NAME' line so one answer picks both a base
// image and the create flags. That line is config, never a selectable option.
func TestRuntimeArgIsConfigNotItem(t *testing.T) {
	pages, err := LoadPages(filepath.Join(appsDir, "comfyui", "wizard"))
	if err != nil || len(pages) == 0 {
		t.Fatalf("load: %v", err)
	}
	p := pages[0]
	if p.Type != "runtime" {
		t.Fatalf("page 0 type = %q, want runtime", p.Type)
	}
	if p.ArgName != "COMFY_GPU" {
		t.Errorf("ArgName = %q, want COMFY_GPU", p.ArgName)
	}
	for _, it := range p.Items {
		if it.Name == "arg" {
			t.Error("the arg config line was parsed as a selectable item")
		}
	}
	if len(p.Items) != 2 {
		t.Errorf("Items = %d, want 2 (amd, nvidia)", len(p.Items))
	}
}

func TestAppliesTo(t *testing.T) {
	p := Page{Applicable: []string{"setup", "build"}}
	if !p.AppliesTo("setup") || !p.AppliesTo("build") || p.AppliesTo("create") {
		t.Error("action gate mismatch")
	}
	star := Page{Applicable: []string{"*"}}
	if !star.AppliesTo("anything") {
		t.Error("'*' should apply to every action")
	}
}

// A detect field is the sole authority: an uninstalled tool must start
// unchecked even when its default state says "on".
func TestDetectOverridesDefault(t *testing.T) {
	it := Item{Name: "x", DefaultOn: true, Detect: []string{"definitely-not-installed-xyz"}}
	if it.PreSelected("/nonexistent-home") {
		t.Error("detect miss should override DefaultOn=true")
	}
	plain := Item{Name: "y", DefaultOn: true}
	if !plain.PreSelected("/nonexistent-home") {
		t.Error("without detect, DefaultOn should decide")
	}
}

// The README panel must actually move when scrolled, and must not scroll past
// the end of the document.
func TestInfoPanelScrolls(t *testing.T) {
	p := newInfoPanel(appsDir)
	a := App{Name: "dev-toolbox", Description: "Dev Toolbox"}
	const w, h = 60, 10

	top := p.view(a, w, h)
	if !p.canScroll(a, w, h) {
		t.Fatal("dev-toolbox README should overflow a 10-line panel")
	}

	p.scroll(10)
	mid := p.view(a, w, h)
	if mid == top {
		t.Error("scrolling produced an identical frame")
	}

	// Far past the end: must clamp, not panic or blank out.
	p.scroll(100000)
	end := p.view(a, w, h)
	if strings.TrimSpace(end) == "" {
		t.Error("over-scrolling blanked the panel")
	}
	p.scroll(-100000)
	if back := p.view(a, w, h); back != top {
		t.Error("scrolling back to 0 did not restore the first frame")
	}
}

// An app with no README must render a placeholder rather than fail. The name is
// deliberately one no app dir can have, so adding a README to a real app cannot
// quietly turn this into a test of nothing.
func TestInfoPanelMissingReadme(t *testing.T) {
	p := newInfoPanel(appsDir)
	out := p.view(App{Name: "no-such-app"}, 50, 6)
	if !strings.Contains(out, "No README.md") {
		t.Errorf("expected placeholder, got:\n%s", out)
	}
}
