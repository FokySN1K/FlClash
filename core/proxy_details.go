package core

import (
	"fmt"

	"github.com/metacubex/mihomo/constant"
)

// ProxyDetailsParams names the node to describe and the target its group tests
// against: the app charts the history of that target, not of whichever URL
// some provider happened to check last.
type ProxyDetailsParams struct {
	ProxyName string `json:"proxy-name"`
	TestUrl   string `json:"test-url"`
}

// DelaySample is one entry of a node's check history. Time is Unix
// milliseconds so the app can say when the last check ran; a zero Delay is a
// check that failed.
type DelaySample struct {
	Time  int64  `json:"time"`
	Delay uint16 `json:"delay"`
}

// ProxyDetails is what a card has no room for: whether the last check of the
// group's target passed, how the node behaved across the checks before it, and
// the transports its protocol offers.
type ProxyDetails struct {
	Alive   bool          `json:"alive"`
	History []DelaySample `json:"history"`
	Udp     bool          `json:"udp"`
	Uot     bool          `json:"uot"`
	Xudp    bool          `json:"xudp"`
	Tfo     bool          `json:"tfo"`
	Mptcp   bool          `json:"mptcp"`
	Smux    bool          `json:"smux"`
}

func handleProxyDetails(params ProxyDetailsParams) (*ProxyDetails, error) {
	proxy := lookupProxy(params.ProxyName)
	if proxy == nil {
		return nil, &MethodError{
			Code:    "proxy_not_found",
			Message: fmt.Sprintf("proxy %q is not part of the applied config", params.ProxyName),
		}
	}
	alive, history := delayState(proxy, params.TestUrl)
	info := proxy.ProxyInfo()
	return &ProxyDetails{
		Alive:   alive,
		History: delaySamples(history),
		Udp:     proxy.SupportUDP(),
		Uot:     proxy.SupportUOT(),
		Xudp:    info.XUDP,
		Tfo:     info.TFO,
		Mptcp:   info.MPTCP,
		Smux:    info.SMUX,
	}, nil
}

// A node measured for the target the group checks keeps that target's verdict
// and history; one checked only elsewhere keeps the history of its default
// test, so the app still has something to show.
func delayState(proxy constant.Proxy, testUrl string) (bool, []constant.DelayHistory) {
	if state, ok := proxy.ExtraDelayHistories()[testUrl]; ok {
		return state.Alive, state.History
	}
	return proxy.AliveForTestUrl(testUrl), proxy.DelayHistory()
}

func delaySamples(history []constant.DelayHistory) []DelaySample {
	samples := make([]DelaySample, len(history))
	for i, record := range history {
		samples[i] = DelaySample{Time: record.Time.UnixMilli(), Delay: record.Delay}
	}
	return samples
}
