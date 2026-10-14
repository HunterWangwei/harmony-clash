# 架构说明

## 版本

- 应用版本：`AppScope/app.json5` 的 `versionName` / `versionCode`，运行时通过 `bundleManager` 读取（`common/AppInfo.ets`）
- 内核版本：`core/MIHOMO_VERSION`，编译时写入 `libmihomo.so`，运行时通过 NAPI `version()` 读取
- 首页底部和「设置 → 关于」同时显示两者

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

- **UI 进程**只负责界面和配置。它和内核之间只通过 REST API 通信，所以同一套界面也能控制远程电脑上的 Clash Verge。实时数据走 WebSocket（首页 `/traffic`、日志页 `/logs`），连接数每 3 秒拉一次 `/connections`；应用进入后台时（`EntryAbility.onBackground` 写入 AppStorage 的 `appForeground`）全部暂停。
- **VPN 进程**由系统拉起，内核运行在这里。UI 启动 VPN 前把配置路径和密钥写入 `files/runtime.json`，VPN 进程读取后启动内核，并把状态写入 `files/vpn_state.json`，供 UI 展示启动失败的原因。
- UI 进程也会加载 `libclashbridge.so`，但只调用 `parseGroups`，在未连接时解析配置里的代理组。

## 启动内核时的强制覆盖

桌面版配置直接在手机上用会出问题，`core/bridge/main.go` 启动前会覆盖这些项：

| 配置项 | 覆盖为 | 原因 |
| --- | --- | --- |
| `external-controller` | `127.0.0.1:19090` + 随机密钥 | 本机其他应用也能访问 127.0.0.1，必须带密钥 |
| `allow-lan` / `dns.listen` | 关闭 | 手机不应向局域网暴露代理和 DNS |
| `mixed-port` | 17890，要求认证（`clash` / 控制接口密钥），清空 `skip-auth-prefixes` | 订阅更新可以经内核代理下载；本机其他应用不能借用代理 |
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

### 4. ArkUI 开发注意事项

- `@Builder` 用位置参数传基本类型时只在首次构建时取值，状态变化后界面不刷新。需要随状态更新的值改为传对象参数，例如首页的 `Stat({ label, value })`
- `LazyForEach` 的数据源对同一个监听器只能用一套通知接口。`common/ListSource.ets` 统一用 `onDatasetChange`，与 `onDataReloaded` / `onDataAdd` 混用会报错 401 导致崩溃
- 长列表（日志、代理节点）用 `LazyForEach` 或 `ListItemGroup` 按需构建；高频数据先缓冲再定时批量刷新

### 5. IPv6

VpnConfig 同时配置 IPv4（`198.18.0.1/30`）和 IPv6（`fdfe:dcba:9876::1/126`，与 Mihomo TUN 默认地址一致）地址，以及 `0.0.0.0/0`、`::/0` 两条路由，并设置 `isIPv6Accepted: true`。

鸿蒙 VPN 扩展在解析 `addresses` 时会按每个地址改写 `isAcceptIPv4` / `isAcceptIPv6`，随后才读取显式的 `isIPv4Accepted` / `isIPv6Accepted`，所以以显式字段为准。真机上 IPv4 流量照常进入隧道；IPv6 默认路由是否被系统采纳与网络环境有关，目前观察到隧道只有 IPv6 地址段路由，后续需要在纯 IPv6 网络下继续验证。

### 6. 模拟器无法启动 VPN

首次连接时系统会通过 `com.huawei.hmos.vpndialog` 弹出授权框。部分模拟器镜像没有这个组件，`startVpnExtensionAbility` 不会返回也不会报错。`VpnControl` 加了 60 秒超时，超时后在首页提示原因。

## 安全

- 控制接口只监听 127.0.0.1，密钥首次启动时用系统随机数生成（16 字节），保存在系统 Asset Store（`common/SecretStore.ets`）。旧版本存在 preferences 里的密钥会在首次读取时迁移并删除
- 本地代理端口要求认证，密码与控制接口密钥相同
- 远程模式的密钥同样存 Asset Store；未开启 HTTPS 时设置页会提示密钥明文传输
- 配置和状态文件原子写入（临时文件 + fsync + rename）
- 内核自己的出站连接通过 `protectProcessNet()` 和 `blockedApplications` 排除在 VPN 之外，避免流量回环
- 签名材料只保存在本地 `signing.local.json5`，不入库
