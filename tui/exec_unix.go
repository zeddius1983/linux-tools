package main

import "syscall"

// syscallExec replaces the current process image with the bash backend, so the
// Go front-end leaves no wrapper process behind and bash inherits the terminal
// outright.
func syscallExec(bin string, argv []string, env []string) error {
	return syscall.Exec(bin, argv, env)
}
