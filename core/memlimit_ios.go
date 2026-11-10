package core

import "runtime/debug"

// iOS ends a Network Extension that grows past about 50 MiB, so the collector
// has to work well before that.
func init() {
	debug.SetMemoryLimit(32 << 20)
}
