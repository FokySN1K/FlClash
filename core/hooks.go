package core

import (
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	mihomoHttp "github.com/metacubex/mihomo/component/http"
	"github.com/metacubex/mihomo/component/proxydialer"
	"github.com/metacubex/mihomo/component/updater"
	constant "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func init() {
	// The app drives every inbound from its own lifecycle, so ApplyConfig must
	// leave the ports alone: they stay down until the service starts.
	executor.DisableDefaultListeners()
	mihomoHttp.TLSConfigHook = relaxCertVerify
	adapter.UrlTestHook = func(url string, name string, delay uint16, timedOut bool) {
		sendMessage(DelayMessage, &Delay{Url: url, Name: name, Value: delayValue(delay, timedOut)})
	}
	adapter.UrlTestStartHook = func(url string, name string) {
		sendMessage(DelayStartMessage, &DelayStart{Url: url, Name: name})
	}
	outboundgroup.CheckStartHook = func(group string, url string, proxies []constant.Proxy) {
		if !hasEventListener() {
			return
		}
		names := make([]string, 0, len(proxies))
		for _, proxy := range proxies {
			names = append(names, proxy.Name())
		}
		sendMessage(CheckStartMessage, &CheckStart{Group: group, Url: url, Names: names})
	}
	outboundgroup.CheckEndHook = func(group string, url string) {
		sendMessage(CheckEndMessage, &CheckEnd{Group: group, Url: url})
	}
	statistic.DefaultRequestNotify = func(c statistic.Tracker) {
		notifyProbeRoute(c)
		if hasEventListener() {
			sendMessage(RequestMessage, c)
			watchRequestTraffic(c)
		}
	}
	dns.DefaultQueryNotify = func(record dns.QueryRecord) {
		if hasEventListener() {
			sendMessage(DnsMessage, newDnsQuery(record))
		}
	}
	executor.DefaultProviderLoadedHook = func(providerName string) {
		scheduleReclaimOwnership()
		scheduleLoadMemoryRelease()
		sendMessage(LoadedMessage, providerName)
	}
	updater.GeoUpdateHook = onGeoUpdate
	proxydialer.DefaultLoopNotify = reportDialerLoop
}

// Every dial through a looping dialer fails; one report stands for the burst.
const dialerLoopReportInterval = 3 * time.Second

var dialerLoopReports sync.Map

func reportDialerLoop(proxyName string) {
	now := time.Now()
	if last, ok := dialerLoopReports.Load(proxyName); ok && now.Sub(last.(time.Time)) < dialerLoopReportInterval {
		return
	}
	dialerLoopReports.Store(proxyName, now)
	sendMessage(DialerLoopMessage, proxyName)
}
