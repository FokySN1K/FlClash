package core

import (
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

const directProxyName = "DIRECT"

// RouteTarget is one outbound the applied rules send traffic to, with the
// number of rules that name it. Default marks the outbound unmatched traffic
// leaves by: the MATCH rule's, or the one the mode sends everything to.
type RouteTarget struct {
	Name    string `json:"name"`
	Rules   int    `json:"rules"`
	Default bool   `json:"default"`
}

// handleRouteTargets lists the outbounds in the order the rules first reach
// them, so the host can ask each one where its traffic leaves by. The list
// follows the Core's compiled rules rather than the profile's: scripts and
// overrides rewrite them on the way in.
func handleRouteTargets() []RouteTarget {
	switch tunnel.Mode() {
	case tunnel.Direct:
		return modeRouteTargets(directProxyName)
	case tunnel.Global:
		return modeRouteTargets(globalProxyName)
	}
	rules := tunnel.Rules()
	targets := make([]RouteTarget, 0, len(rules))
	at := make(map[string]int, len(rules))
	for _, rule := range rules {
		name := rule.Adapter()
		if !leavesByAddress(name) {
			continue
		}
		if index, ok := at[name]; ok {
			targets[index].Rules++
			continue
		}
		at[name] = len(targets)
		targets = append(targets, RouteTarget{Name: name, Rules: 1})
	}
	if index, ok := at[matchTarget()]; ok {
		targets[index].Default = true
	}
	return targets
}

// The tunnel sends every connection straight to one target in these modes,
// whatever the rules say.
func modeRouteTargets(name string) []RouteTarget {
	if !leavesByAddress(name) {
		return []RouteTarget{}
	}
	return []RouteTarget{{Name: name, Default: true}}
}

// defaultRouteName is the outbound a lookup leaves by when it names no target.
func defaultRouteName() string {
	switch tunnel.Mode() {
	case tunnel.Direct:
		return directProxyName
	case tunnel.Global:
		return globalProxyName
	}
	return matchTarget()
}

// matchTarget is where the rules send whatever they do not name; without a
// MATCH rule the tunnel falls back to DIRECT on its own.
func matchTarget() string {
	for _, rule := range tunnel.Rules() {
		if rule.RuleType() == constant.MATCH {
			return rule.Adapter()
		}
	}
	return ""
}

// leavesByAddress reports whether a target has an address to look up; a
// rejection or a pass hands the connection on instead of leaving by one.
func leavesByAddress(name string) bool {
	proxy := lookupProxy(name)
	if proxy == nil {
		return false
	}
	switch proxy.Type() {
	case constant.Reject, constant.RejectDrop, constant.Pass, constant.PassRule:
		return false
	default:
		return true
	}
}
