package main

import (
	"strings"
	"testing"
)

func TestRenderStateFile(t *testing.T) {
	s := State{
		App:       "fastflowlm",
		Action:    "setup",
		BuildArgs: []string{"--build-arg", "FLM_REF=v0.9.12"},
		Variant:   "nvidia",
		Pages:     map[string][]string{"00-statusline": {"statusline"}},
	}
	out := s.Render()

	for _, want := range []string{
		`APP="fastflowlm"`,
		`ACTION="setup"`,
		`BUILD_ARGS="--build-arg FLM_REF=v0.9.12"`,
		`VARIANT="nvidia"`,
		`PAGE_00_statusline="statusline"`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// The state file is sourced by bash, so page names that are not valid shell
// identifiers must be sanitised the same way lib/wizard.sh re-sanitises them.
func TestVarSuffix(t *testing.T) {
	cases := map[string]string{
		"00-statusline": "00_statusline",
		"00-tools":      "00_tools",
		"01-a.b-c":      "01_a_b_c",
	}
	for in, want := range cases {
		if got := varSuffix(in); got != want {
			t.Errorf("varSuffix(%q) = %q, want %q", in, got, want)
		}
	}
}

// Values are interpolated into a double-quoted bash assignment, so anything
// that could break out of the quotes or trigger expansion must be escaped.
func TestShellQuoteEscapes(t *testing.T) {
	cases := map[string]string{
		`plain`:      `"plain"`,
		`a"b`:        `"a\"b"`,
		`$HOME`:      `"\$HOME"`,
		"`id`":       "\"\\`id\\`\"",
		`back\slash`: `"back\\slash"`,
	}
	for in, want := range cases {
		if got := shellQuote(in); got != want {
			t.Errorf("shellQuote(%q) = %s, want %s", in, got, want)
		}
	}
}

func TestEmptyStateRendersEmptyValues(t *testing.T) {
	out := State{App: "x", Action: "build", Pages: map[string][]string{}}.Render()
	if !strings.Contains(out, `BUILD_ARGS=""`) || !strings.Contains(out, `VARIANT=""`) {
		t.Errorf("empty selections should still render empty vars:\n%s", out)
	}
}

func TestSuperscript(t *testing.T) {
	for in, want := range map[int]string{0: "⁰", 6: "⁶", 12: "¹²", 23: "²³"} {
		if got := superscript(in); got != want {
			t.Errorf("superscript(%d) = %q, want %q", in, got, want)
		}
	}
}

// pad counts runes, not bytes: a multi-byte glyph must not eat column width.
func TestPadCountsRunes(t *testing.T) {
	if got := pad("● running", 11); len([]rune(got)) != 11 {
		t.Errorf("pad produced %d runes, want 11", len([]rune(got)))
	}
	if got := pad("toolong-value", 4); got != "toolong-value" {
		t.Errorf("pad must not truncate, got %q", got)
	}
}
