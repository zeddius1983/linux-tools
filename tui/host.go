package main

import (
	"os"
	"os/exec"
)

// This binary is meant to run on the host, where podman, distrobox and tools
// are all on PATH. During development it is often run from inside a Distrobox
// container instead, where none of them exist — and exec.Command simply fails,
// which would silently report every app as "not built" with no visible error.
//
// When running inside a container, commands are therefore routed through
// distrobox-host-exec, the same escape hatch the repo's wrapper scripts use.

func insideContainer() bool {
	for _, marker := range []string{"/run/.containerenv", "/.dockerenv"} {
		if _, err := os.Stat(marker); err == nil {
			return true
		}
	}
	return os.Getenv("CONTAINER_ID") != ""
}

// hostExecPath is the distrobox-host-exec binary to delegate through, or "" when
// commands should run directly.
var hostExecPath = resolveHostExec()

func resolveHostExec() string {
	if !insideContainer() {
		return ""
	}
	p, err := exec.LookPath("distrobox-host-exec")
	if err != nil {
		return ""
	}
	return p
}

// hostCommand builds a command that runs on the host, transparently delegating
// through distrobox-host-exec when this process is containerised.
func hostCommand(name string, args ...string) *exec.Cmd {
	if hostExecPath != "" {
		return exec.Command(hostExecPath, append([]string{name}, args...)...)
	}
	return exec.Command(name, args...)
}

// hostNote describes the delegation for the footer, or "" when running natively.
func hostNote() string {
	if hostExecPath == "" {
		return ""
	}
	return "via distrobox-host-exec"
}
