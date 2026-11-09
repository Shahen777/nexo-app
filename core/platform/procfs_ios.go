package platform

import "net"

// iOS keeps no procfs and the Network Extension cannot see other apps' sockets.
func QuerySocketUidFromProcFs(_, _ net.Addr) int {
	return -1
}
