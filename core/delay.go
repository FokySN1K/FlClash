package core

import (
	"context"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/outboundgroup/probequeue"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/constant"
)

const (
	delayTestConcurrency    = 50
	defaultTestURL          = "https://www.gstatic.com/generate_204"
	defaultDelayTestTimeout = 5 * time.Second
)

var (
	delayTestSlots     = make(slots, delayTestConcurrency)
	anyDelayTestStatus utils.IntRanges[uint16]

	testURL                 atomic.Pointer[string]
	missingDelayTestProxyAt atomic.Int64
)

func setTestURL(url string) {
	if url == "" {
		return
	}
	constant.DefaultTestURL = url
	testURL.Store(&url)
}

func currentTestURL() string {
	if url := testURL.Load(); url != nil && *url != "" {
		return *url
	}
	return defaultTestURL
}

const (
	delayTimedOut int32 = -1
	delayFailed   int32 = -2
)

func delayValue(delay uint16, timedOut bool) int32 {
	switch {
	case delay > 0:
		return int32(delay)
	case timedOut:
		return delayTimedOut
	default:
		return delayFailed
	}
}

// A name the tunnel does not know is what an apply that fell back to the
// default config looks like: every node of the profile fails its test. Say so
// once a second, not once per node, so the log names the real failure.
func reportMissingDelayTestProxy(name string) {
	now := time.Now().UnixNano()
	last := missingDelayTestProxyAt.Load()
	if last != 0 && now-last < int64(time.Second) {
		return
	}
	if !missingDelayTestProxyAt.CompareAndSwap(last, now) {
		return
	}
	logError("delay test: %q is not part of the applied config", name)
}

// A nil answer means the test never got a slot, which says nothing about the proxy.
func handleTestDelay(params *TestDelayParams) *Delay {
	url := params.TestUrl
	if url == "" {
		url = currentTestURL()
	}
	result := &Delay{Name: params.ProxyName, Url: url, Value: delayFailed}

	proxy := lookupProxy(params.ProxyName)
	if proxy == nil {
		reportMissingDelayTestProxy(params.ProxyName)
		return result
	}

	timeout := timeoutFromMillis(params.Timeout, defaultDelayTestTimeout)
	if !delayTestSlots.acquireWithin(context.Background(), timeout) {
		return nil
	}
	defer delayTestSlots.release()

	// The test joins the shared queue like every group's own sweep: when the
	// sweep already asks the same node the same question, the queue shares that
	// measurement instead of loading the path twice.
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	delay, err := probequeue.TestProxyWithBudget(ctx, proxy, url, anyDelayTestStatus, timeout)
	if err != nil {
		delay = 0
	}
	result.Value = delayValue(delay, ctx.Err() != nil)
	return result
}

// A group's own check probes every member at once, so the single-node budget
// the app sends would cut the slow members off and make them look dead; the
// floor keeps a group test meaningful and still bounds it.
const groupDelayTestTimeout = 30 * time.Second

// A test through one dial exercises one member and leaves the group's own
// choice untouched, so a pool would keep routing to a member it excluded and
// an ordered fallback would never retry a recovered head. A group that knows
// how to check itself runs its own check instead; the members it measures
// reach the app through UrlTestHook, and the value returned describes the
// group's route as it stands after the check.
func handleTestGroupDelay(params *TestDelayParams) *Delay {
	group, ok := adapterAs[outboundgroup.ProxyGroup](lookupProxy(params.ProxyName))
	if !ok {
		return handleTestDelay(params)
	}
	tester, ok := group.(outboundgroup.SelfTester)
	if !ok {
		return handleTestDelay(params)
	}

	url, expected := tester.SelfTestTarget()
	if url == "" {
		url = currentTestURL()
	}
	result := &Delay{Name: params.ProxyName, Url: url, Value: delayFailed}

	timeout := timeoutFromMillis(params.Timeout, defaultDelayTestTimeout)
	if timeout < groupDelayTestTimeout {
		timeout = groupDelayTestTimeout
	}
	if !delayTestSlots.acquireWithin(context.Background(), timeout) {
		return nil
	}
	defer delayTestSlots.release()

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	results, err := group.URLTest(ctx, url, expected)
	if err != nil {
		result.Value = delayValue(0, ctx.Err() != nil)
		return result
	}
	result.Value = delayValue(groupDelay(results, group.Now()), ctx.Err() != nil)
	return result
}

// The delay of a group is the delay of the route it now uses; when this check
// left that member out, the fastest measured one stands in.
func groupDelay(results map[string]uint16, now string) uint16 {
	if delay, ok := results[now]; ok {
		return delay
	}
	var best uint16
	for _, delay := range results {
		if best == 0 || delay < best {
			best = delay
		}
	}
	return best
}
