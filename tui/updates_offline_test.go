package main

import (
	"context"
	"testing"
)

// An items-cmd whose fetch fails still exits 0 with only its moving entry;
// that must surface as an error, or the empty answer is cached for hours.
func TestVersionItemsOnlyMovingIsError(t *testing.T) {
	// Run the items-cmd here rather than through distrobox-host-exec: this
	// tests the parsing, not the delegation, and under `go test` inside a
	// Distrobox container the delegated call exits 127 with no output — which
	// the first case below would then pass by accident.
	saved := hostExecPath
	hostExecPath = ""
	t.Cleanup(func() { hostExecPath = saved })

	p := Page{ArgName: "CODEX_REF", ItemsCmd: `{ printf '%s\n' latest; false | tail -10; }`}
	if _, err := versionItems(context.Background(), p); err == nil {
		t.Fatal("expected an error when only a moving entry is listed")
	}
	p.ItemsCmd = `printf '%s\n' latest 1.2.0`
	items, err := versionItems(context.Background(), p)
	if err != nil || len(items) != 2 {
		t.Fatalf("got %v, %v", items, err)
	}
}
