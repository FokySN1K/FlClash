package core

import (
	"net/http"
	"slices"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/rules"
	"github.com/metacubex/mihomo/tunnel"
)

// withRouteRules installs the proxies, the rules and the mode a test resolves
// routes under, and puts the tunnel back the way it was afterwards.
func withRouteRules(t *testing.T, mode tunnel.TunnelMode, proxies map[string]constant.Proxy, parsed ...constant.Rule) {
	t.Helper()
	tunnel.UpdateProxies(proxies, nil)
	tunnel.UpdateRules(parsed, nil, nil)
	previous := tunnel.Mode()
	tunnel.SetMode(mode)
	t.Cleanup(func() {
		tunnel.SetMode(previous)
		tunnel.UpdateProxies(nil, nil)
		tunnel.UpdateRules(nil, nil, nil)
	})
}

func routeRule(t *testing.T, ruleType, payload, target string) constant.Rule {
	t.Helper()
	rule, err := rules.ParseRule(ruleType, payload, target, nil, nil)
	if err != nil {
		t.Fatalf("ParseRule(%s, %q, %s): %v", ruleType, payload, target, err)
	}
	return rule
}

func TestRouteTargetsCountWhatTheRulesPointAt(t *testing.T) {
	withRouteRules(t, tunnel.Rule,
		map[string]constant.Proxy{"Proxy": selectorGroup(t, "Proxy", "node-a"), "DIRECT": namedProxy("DIRECT")},
		routeRule(t, "IP-CIDR", "127.0.0.0/8", "DIRECT"),
		routeRule(t, "DOMAIN-SUFFIX", "ru", "Proxy"),
		routeRule(t, "DOMAIN", "example.com", "Proxy"),
		routeRule(t, "MATCH", "", "Proxy"),
	)

	want := []RouteTarget{{Name: "DIRECT", Rules: 1}, {Name: "Proxy", Rules: 3, Default: true}}
	if got := handleRouteTargets(); !slices.Equal(got, want) {
		t.Errorf("targets = %+v, want %+v", got, want)
	}
}

func TestRouteTargetsSkipRulesWithoutAnExit(t *testing.T) {
	withRouteRules(t, tunnel.Rule,
		map[string]constant.Proxy{
			"Proxy":       selectorGroup(t, "Proxy", "node-a"),
			"DIRECT":      namedProxy("DIRECT"),
			"REJECT":      adapter.NewProxy(outbound.NewReject()),
			"REJECT-DROP": adapter.NewProxy(outbound.NewRejectDrop()),
			"PASS":        adapter.NewProxy(outbound.NewPass()),
		},
		routeRule(t, "DOMAIN-SUFFIX", "ads.example", "REJECT"),
		routeRule(t, "DOMAIN-SUFFIX", "drop.example", "REJECT-DROP"),
		routeRule(t, "DOMAIN-SUFFIX", "pass.example", "PASS"),
		routeRule(t, "MATCH", "", "Proxy"),
	)

	want := []RouteTarget{{Name: "Proxy", Rules: 1, Default: true}}
	if got := handleRouteTargets(); !slices.Equal(got, want) {
		t.Errorf("targets = %+v, want the rejections and the pass left out: %+v", got, want)
	}
}

func TestRouteTargetsFollowTheMode(t *testing.T) {
	withRouteRules(t, tunnel.Global,
		map[string]constant.Proxy{"GLOBAL": namedProxy("GLOBAL"), "DIRECT": namedProxy("DIRECT")},
		routeRule(t, "MATCH", "", "DIRECT"),
	)

	want := []RouteTarget{{Name: "GLOBAL", Default: true}}
	if got := handleRouteTargets(); !slices.Equal(got, want) {
		t.Errorf("targets in global mode = %+v, want %+v", got, want)
	}
	if got := defaultRouteName(); got != "GLOBAL" {
		t.Errorf("default route in global mode = %q, want GLOBAL", got)
	}

	tunnel.SetMode(tunnel.Direct)
	want = []RouteTarget{{Name: "DIRECT", Default: true}}
	if got := handleRouteTargets(); !slices.Equal(got, want) {
		t.Errorf("targets in direct mode = %+v, want %+v", got, want)
	}
	if got := defaultRouteName(); got != "DIRECT" {
		t.Errorf("default route in direct mode = %q, want DIRECT", got)
	}
}

func TestRouteTargetsWithoutRulesLeaveNoDefault(t *testing.T) {
	withRouteRules(t, tunnel.Rule, map[string]constant.Proxy{"DIRECT": namedProxy("DIRECT")})

	if got := handleRouteTargets(); len(got) != 0 {
		t.Errorf("targets = %+v, want none without rules", got)
	}
	if got := defaultRouteName(); got != "" {
		t.Errorf("default route = %q, want none without a MATCH rule", got)
	}
}

func TestTheRoutedLookupLeavesByTheDefaultTarget(t *testing.T) {
	recordRoutes(t)
	withRouteRules(t, tunnel.Rule,
		map[string]constant.Proxy{
			"Proxy":  selectorGroup(t, "Proxy", "node-a"),
			"DIRECT": namedProxy("DIRECT"),
			"node-a": namedProxy("node-a"),
		},
		routeRule(t, "IP-CIDR", "127.0.0.0/8", "DIRECT"),
		routeRule(t, "MATCH", "", "Proxy"),
	)
	server := probeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ip=203.0.113.7"))
	})
	host := strings.TrimPrefix(server.URL, "http://")

	direct := exitName(namedProxy("DIRECT"))
	if got := resolveExit(host, ""); got != direct {
		t.Fatalf("resolved exit = %q, want the source's own rule, %q", got, direct)
	}

	answer := handleOutboundIp(&OutboundIpParams{Urls: []string{server.URL}, Timeout: 4000})
	want := []RouteHit{{Host: host, Proxy: "Proxy", Exit: exitName(namedProxy("node-a"))}}
	if answer.Error != "" || !slices.Equal(answer.Hits, want) {
		t.Errorf("lookup = %+v, want it to leave by the default target: %+v", answer, want)
	}
}
