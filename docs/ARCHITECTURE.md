# 架构说明

## 分层

```
ArkTS UI（EntryAbility 进程）
  │  HTTP / WebSocket → 127.0.0.1:19090（Mihomo RESTful API，带随机密钥）
  │  vpnExtension.startVpnExtensionAbility()
  ▼
ClashVpnAbility（独立的 :vpn 进程）
  │  创建系统 VPN，拿到 TUN fd
  │  NAPI：libclashbridge.so（C++）
  ▼
libmihomo.so（Go c-shared）
  core/bridge：解析配置、强制覆盖手机上必须的选项、启动内核
  Mihomo 内核 + gVisor 网络栈，读写 TUN fd
```

- **UI 进程**只负责界面和配置。它和内核之间只通过 REST API 通信，所以同一套界面也能控制远程电脑上的 Clash Verge。
- **VPN 进程**由系统拉起，内核运行在这里。UI 启动 VPN 前把配置路径和密钥写入 `files/runtime.json`，VPN 进程读取后启动内核，并把状态写入 `files/vpn_state.json`，供 UI 展示启动失败的原因。
- UI 进程也会加载 `libclashbridge.so`，但只调用 `parseGroups`，在未连接时解析配置里的代理组。

## 启动内核时的强制覆盖

桌面版配置直接在手机上用会出问题，`core/bridge/main.go` 启动前会覆盖这些项：

| 配置项 | 覆盖为 | 原因 |
| --- | --- | --- |
| `external-controller` | `127.0.0.1:19090` + 随机密钥 | 本机其他应用也能访问 127.0.0.1，必须带密钥 |
| `allow-lan` / `dns.listen` | 关闭 | 手机不应向局域网暴露代理和 DNS |
| `mixed-port` | 17890 | 订阅更新可以经内核代理下载 |
| `tun` | 启用，绑定 VPN fd，gVisor 栈，关闭自动路由 | 路由由系统 VPN 负责 |
| `tun.mtu` | 1500 | 必须与 VpnConfig 一致，桌面配置常写 9000 |
| `dns` | 未启用时开启 fake-ip | 规则分流依赖内核处理 DNS |
| GeoX 下载地址 | 默认 GitHub 地址换成 jsDelivr 镜像 | 国内网络常无法访问 GitHub |

## 关键技术问题

### 1. Go c-shared 无法被 dlopen

官方 Go 为 c-shared 生成 initial-exec TLS 重定位。鸿蒙的加载器基于 musl，不为运行时 dlopen 的库预留静态 TLS，直接报错拒绝。解决方法是用补丁版 Go 工具链，改用 TLSDESC，详见 [BUILD.md](BUILD.md)。

### 2. TUN fd 上的 fstat 被拒绝

gVisor 的 `fdbased.IsSocketFD` 会对 fd 调 `fstat` 来判断它是不是 socket。鸿蒙不允许对 VPN 交给应用的 TUN fd 调 `fstat`，返回 `EACCES`。之前 TUN 因此启动失败，内核把 `tun.enable` 改回 false，但界面仍显示已连接，系统流量全部丢弃。

`core/gvisor` 是 `github.com/metacubex/gvisor` 的副本（版本见 `core/bridge/go.mod`），通过 `replace` 引用。唯一的改动在 `pkg/tcpip/link/fdbased/endpoint.go`：`fstat` 返回 `EACCES` / `EPERM` 时按"不是 socket"处理。升级 gVisor 后需要重新应用这处修改。

### 3. 内核日志

鸿蒙会丢弃应用的 stdout，所以 `core/bridge` 订阅 Mihomo 的日志，通过 `OH_LOG_Print` 转发到 hilog，tag 为 `Mihomo`。

### 4. 模拟器无法启动 VPN

首次连接时系统会通过 `com.huawei.hmos.vpndialog` 弹出授权框。部分模拟器镜像没有这个组件，`startVpnExtensionAbility` 不会返回也不会报错。`VpnControl` 加了 60 秒超时，超时后在首页提示原因。

## 安全

- 控制接口只监听 127.0.0.1，密钥首次启动时用系统随机数生成（16 字节）
- 内核自己的出站连接通过 `protectProcessNet()` 和 `blockedApplications` 排除在 VPN 之外，避免流量回环
- 签名材料只保存在本地 `signing.local.json5`，不入库
