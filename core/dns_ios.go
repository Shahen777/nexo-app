package core

// The Network Extension hands the system its DNS servers through NEDNSSettings,
// and mihomo has no hook for the iOS resolver, so there is nothing to update.
func handleUpdateDns(string) {}
