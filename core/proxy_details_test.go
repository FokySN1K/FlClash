package core

import (
	"context"
	"errors"
	"net/http"
	"testing"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// withDetailsProxy puts one node into the tunnel, so lookupProxy finds it, and
// takes it out again when the test ends.
func withDetailsProxy(t *testing.T, proxy constant.Proxy) constant.Proxy {
	t.Helper()
	tunnel.UpdateProxies(map[string]constant.Proxy{proxy.Name(): proxy}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	return proxy
}

func checkProxy(t *testing.T, proxy constant.Proxy, url string) {
	t.Helper()
	if _, err := proxy.URLTest(context.Background(), url, nil); err != nil {
		t.Fatalf("URLTest(%s): %v", url, err)
	}
}

func TestProxyDetailsFollowTheTestTarget(t *testing.T) {
	proxy := withDetailsProxy(t, namedProxy("node-a"))
	first := probeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	second := probeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})

	checkProxy(t, proxy, first.URL)
	checkProxy(t, proxy, first.URL)
	checkProxy(t, proxy, second.URL)

	details, err := handleProxyDetails(ProxyDetailsParams{ProxyName: "node-a", TestUrl: first.URL})
	if err != nil {
		t.Fatalf("handleProxyDetails: %v", err)
	}
	if !details.Alive || len(details.History) != 2 {
		t.Fatalf("details for the first target = %+v, want its two checks", details)
	}
	for _, sample := range details.History {
		if sample.Delay == 0 || sample.Time == 0 {
			t.Errorf("sample = %+v, want a delay and a timestamp", sample)
		}
	}

	details, err = handleProxyDetails(ProxyDetailsParams{ProxyName: "node-a", TestUrl: second.URL})
	if err != nil {
		t.Fatalf("handleProxyDetails: %v", err)
	}
	if !details.Alive || len(details.History) != 1 {
		t.Errorf("history for the second target = %+v, want only its own check", details)
	}

	details, err = handleProxyDetails(ProxyDetailsParams{ProxyName: "node-a"})
	if err != nil {
		t.Fatalf("handleProxyDetails: %v", err)
	}
	if len(details.History) != 3 {
		t.Errorf("history without a target = %+v, want every check of the default one", details)
	}
}

func TestProxyDetailsMarkAFailedCheckDead(t *testing.T) {
	proxy := withDetailsProxy(t, namedProxy("node-a"))
	server := probeServer(t, func(http.ResponseWriter, *http.Request) {})
	url := server.URL
	server.Close()

	if _, err := proxy.URLTest(context.Background(), url, nil); err == nil {
		t.Fatal("URLTest against a closed server passed")
	}

	details, err := handleProxyDetails(ProxyDetailsParams{ProxyName: "node-a", TestUrl: url})
	if err != nil {
		t.Fatalf("handleProxyDetails: %v", err)
	}
	if details.Alive {
		t.Error("a node whose last check failed is reported alive")
	}
	if len(details.History) != 1 || details.History[0].Delay != 0 {
		t.Errorf("history = %+v, want the one failed check", details.History)
	}
}

func TestProxyDetailsRejectAnUnknownProxy(t *testing.T) {
	tunnel.UpdateProxies(nil, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	details, err := handleProxyDetails(ProxyDetailsParams{ProxyName: "missing"})
	if details != nil {
		t.Errorf("details = %+v, want none for a name the tunnel does not hold", details)
	}
	var methodErr *MethodError
	if !errors.As(err, &methodErr) || methodErr.Code != "proxy_not_found" {
		t.Fatalf("error = %v, want a proxy_not_found method error", err)
	}
}

func TestProxyDetailsReportTheProtocolFeatures(t *testing.T) {
	proxy := adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{
		BasicOption: outbound.BasicOption{TFO: true, MPTCP: true},
		Name:        "node-a",
	}))
	withDetailsProxy(t, proxy)

	details, err := handleProxyDetails(ProxyDetailsParams{ProxyName: "node-a"})
	if err != nil {
		t.Fatalf("handleProxyDetails: %v", err)
	}
	if !details.Udp {
		t.Error("a direct node dials UDP but is reported without it")
	}
	if details.Uot {
		t.Error("a direct node has no UDP over TCP but is reported with it")
	}
	if !details.Tfo || !details.Mptcp || details.Xudp || details.Smux {
		t.Errorf("details = %+v, want the TFO and MPTCP the node was built with", details)
	}
}
