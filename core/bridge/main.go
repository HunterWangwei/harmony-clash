// Package main exports a small C ABI around the Mihomo core so the HarmonyOS
// NAPI layer can start/stop it inside the app process.
package main

/*
#cgo LDFLAGS: -lhilog_ndk.z
#include <stdlib.h>
#include <hilog/log.h>

// hilog's format string must be a literal; pass the message through %{public}s.
static void hilog_print(int level, const char *msg) {
	OH_LOG_Print(LOG_APP, (LogLevel)level, 0x0000, "Mihomo", "%{public}s", msg);
}
*/
import "C"

import (
	"encoding/json"
	"os"
	"regexp"
	"strings"
	"sync"
	"unsafe"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/log"
)

var (
	mu      sync.Mutex
	running bool
)

func cstr(s string) *C.char { return C.CString(s) }

// Local HTTP/SOCKS port; loopback only because allow-lan is forced off.
// The UI downloads subscriptions through it while the core is running.
const localMixedPort = 17890

// MTU of the system VPN interface; must match TUN_MTU in entry/src/main/ets/common/Runtime.ets.
const tunMTU = 1500

// GitHub release downloads are often unreachable from mainland networks; only
// replace URLs that are still Mihomo's defaults so profile overrides win.
const mirror = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/"

func mirrorGeo(u string) string {
	const def = "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/"
	if strings.HasPrefix(u, def) {
		return mirror + strings.TrimPrefix(u, def)
	}
	return u
}

// startCore parses the profile, applies overrides and (re)starts the core. Caller holds mu.
// When tunFd > 0 the TUN inbound is forced on and bound to that fd from the system VPN.
func startCore(home, file, controller, secret string, tunFd int) error {
	constant.SetHomeDir(home)
	constant.SetConfig(file)

	buf, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	raw, err := config.UnmarshalRawConfig(buf)
	if err != nil {
		return err
	}
	raw.ExternalController = controller
	raw.Secret = secret
	// Ports bound by desktop profiles are irrelevant on the phone and may collide.
	raw.ExternalControllerUnix = ""
	raw.ExternalControllerPipe = ""
	raw.ExternalControllerTLS = ""
	raw.ExternalUI = ""
	// Never expose proxy ports or DNS to the LAN from a phone.
	raw.AllowLan = false
	raw.MixedPort = localMixedPort
	raw.DNS.Listen = ""
	raw.GeoXUrl.GeoIp = mirrorGeo(raw.GeoXUrl.GeoIp)
	raw.GeoXUrl.Mmdb = mirrorGeo(raw.GeoXUrl.Mmdb)
	raw.GeoXUrl.ASN = mirrorGeo(raw.GeoXUrl.ASN)
	raw.GeoXUrl.GeoSite = mirrorGeo(raw.GeoXUrl.GeoSite)

	if tunFd > 0 {
		raw.Tun.Enable = true
		raw.Tun.FileDescriptor = tunFd
		raw.Tun.Stack = constant.TunGvisor
		raw.Tun.AutoRoute = false
		raw.Tun.AutoRedirect = false
		raw.Tun.AutoDetectInterface = false
		raw.Tun.StrictRoute = false
		raw.Tun.DNSHijack = []string{"any:53"}
		// Must match the VpnConfig MTU; desktop profiles often set 9000.
		raw.Tun.MTU = tunMTU
		// Routing is decided by rules, so DNS must be handled by the core.
		if !raw.DNS.Enable {
			raw.DNS.Enable = true
			raw.DNS.EnhancedMode = constant.DNSFakeIP
			raw.DNS.FakeIPRange = "198.18.0.1/16"
			if len(raw.DNS.NameServer) == 0 {
				raw.DNS.NameServer = []string{"223.5.5.5", "119.29.29.29"}
			}
			if len(raw.DNS.DefaultNameserver) == 0 {
				raw.DNS.DefaultNameserver = []string{"223.5.5.5", "119.29.29.29"}
			}
		}
	} else {
		raw.Tun.Enable = false
	}

	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		return err
	}
	if running {
		executor.Shutdown()
		running = false
	}
	hub.ApplyConfig(cfg)
	running = true
	log.Infoln("mihomo started from %s (tun fd %d)", file, tunFd)
	return nil
}

// MihomoStartTun starts the core with TUN bound to the given VPN fd.
// Returns NULL on success or an error message the caller must free with MihomoFree.
//
//export MihomoStartTun
func MihomoStartTun(homeDir, configFile, controller, secret *C.char, tunFd C.int) *C.char {
	mu.Lock()
	defer mu.Unlock()
	err := startCore(C.GoString(homeDir), C.GoString(configFile), C.GoString(controller), C.GoString(secret), int(tunFd))
	if err != nil {
		return cstr(err.Error())
	}
	return nil
}

// MihomoStart loads the config file and starts the core.
// controller is the external-controller address (e.g. "127.0.0.1:9090").
// Returns NULL on success or an error message the caller must free with MihomoFree.
//
//export MihomoStart
func MihomoStart(homeDir, configFile, controller, secret *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()
	err := startCore(C.GoString(homeDir), C.GoString(configFile), C.GoString(controller), C.GoString(secret), 0)
	if err != nil {
		return cstr(err.Error())
	}
	return nil
}

// MihomoStop shuts down all listeners. Safe to call when not running.
//
//export MihomoStop
func MihomoStop() {
	mu.Lock()
	defer mu.Unlock()
	if running {
		executor.Shutdown()
		// An empty config closes the REST controller listeners.
		route.ReCreateServer(&route.Config{})
		running = false
	}
}

// MihomoIsRunning returns 1 when the core is active.
//
//export MihomoIsRunning
func MihomoIsRunning() C.int {
	mu.Lock()
	defer mu.Unlock()
	if running {
		return 1
	}
	return 0
}

// MihomoVersion returns the core version; free with MihomoFree.
//
//export MihomoVersion
func MihomoVersion() *C.char {
	return cstr(constant.Version)
}

//export MihomoFree
func MihomoFree(p *C.char) {
	C.free(unsafe.Pointer(p))
}

type groupInfo struct {
	Name string   `json:"name"`
	Type string   `json:"type"`
	Now  string   `json:"now"`
	All  []string `json:"all"`
	// Providers referenced via "use"; their nodes are only known after the core starts.
	Use []string `json:"use"`
}

type parseResult struct {
	Groups []groupInfo `json:"groups"`
	Error  string      `json:"error"`
}

var groupTypes = map[string]string{
	"select":       "Selector",
	"url-test":     "URLTest",
	"fallback":     "Fallback",
	"load-balance": "LoadBalance",
	"relay":        "Relay",
}

func strList(v any) []string {
	out := []string{}
	if arr, ok := v.([]any); ok {
		for _, x := range arr {
			if s, ok := x.(string); ok {
				out = append(out, s)
			}
		}
	}
	return out
}

func truthy(v any) bool {
	b, ok := v.(bool)
	return ok && b
}

// applyFilter mirrors Mihomo's backtick-separated filter / exclude-filter semantics (best effort).
func applyFilter(names []string, filter string, exclude bool) []string {
	if filter == "" {
		return names
	}
	var res []*regexp.Regexp
	for _, f := range strings.Split(filter, "`") {
		if r, err := regexp.Compile(f); err == nil {
			res = append(res, r)
		}
	}
	if len(res) == 0 {
		return names
	}
	out := []string{}
	for _, n := range names {
		hit := false
		for _, r := range res {
			if r.MatchString(n) {
				hit = true
				break
			}
		}
		if hit != exclude {
			out = append(out, n)
		}
	}
	return out
}

// MihomoParseGroups reads proxy groups from a profile without starting the core,
// so nodes can be browsed and pre-selected before connecting. Returns JSON; free with MihomoFree.
//
//export MihomoParseGroups
func MihomoParseGroups(configFile *C.char) *C.char {
	res := parseResult{Groups: []groupInfo{}}
	encode := func() *C.char {
		b, _ := json.Marshal(res)
		return cstr(string(b))
	}
	buf, err := os.ReadFile(C.GoString(configFile))
	if err != nil {
		res.Error = err.Error()
		return encode()
	}
	raw, err := config.UnmarshalRawConfig(buf)
	if err != nil {
		res.Error = err.Error()
		return encode()
	}

	proxyNames := []string{}
	for _, p := range raw.Proxy {
		if n, ok := p["name"].(string); ok {
			proxyNames = append(proxyNames, n)
		}
	}
	groupNames := []string{}
	for _, g := range raw.ProxyGroup {
		if n, ok := g["name"].(string); ok {
			groupNames = append(groupNames, n)
		}
	}

	for _, g := range raw.ProxyGroup {
		name, _ := g["name"].(string)
		typ, _ := g["type"].(string)
		if name == "" {
			continue
		}
		all := strList(g["proxies"])
		if truthy(g["include-all"]) || truthy(g["include-all-proxies"]) {
			extra := proxyNames
			if f, ok := g["filter"].(string); ok {
				extra = applyFilter(extra, f, false)
			}
			if f, ok := g["exclude-filter"].(string); ok {
				extra = applyFilter(extra, f, true)
			}
			all = append(all, extra...)
		}
		mapped, ok := groupTypes[typ]
		if !ok {
			mapped = typ
		}
		info := groupInfo{Name: name, Type: mapped, All: all, Use: strList(g["use"])}
		if len(all) > 0 {
			info.Now = all[0]
		}
		res.Groups = append(res.Groups, info)
	}

	// GLOBAL is synthesized by Mihomo from every group and proxy.
	globalAll := append([]string{"DIRECT", "REJECT"}, groupNames...)
	globalAll = append(globalAll, proxyNames...)
	global := groupInfo{Name: "GLOBAL", Type: "Selector", All: globalAll, Use: []string{}}
	if len(groupNames) > 0 {
		global.Now = groupNames[0]
	} else {
		global.Now = "DIRECT"
	}
	res.Groups = append([]groupInfo{global}, res.Groups...)
	return encode()
}

// stdout is discarded on HarmonyOS, so mirror core logs into hilog for `hdc hilog`.
func init() {
	sub := log.Subscribe()
	go func() {
		for ev := range sub {
			lv := C.int(C.LOG_INFO)
			switch ev.LogLevel {
			case log.DEBUG:
				lv = C.LOG_DEBUG
			case log.WARNING:
				lv = C.LOG_WARN
			case log.ERROR:
				lv = C.LOG_ERROR
			}
			msg := C.CString(ev.Payload)
			C.hilog_print(lv, msg)
			C.free(unsafe.Pointer(msg))
		}
	}()
}

func main() {}
