package main

import (
	"context"
	"testing"
)

// An items-cmd whose fetch fails still exits 0 with only its moving entry;
// that must surface as an error, or the empty answer is cached for hours.
func TestVersionItemsOnlyMovingIsError(t *testing.T) {
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
