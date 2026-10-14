# 优化记录

按优先级分批推进，每完成一批更新本文件并提交。状态：`[ ]` 待做 · `[x]` 已完成 · `[-]` 暂缓

## 批次 0：阻断问题

- [x] 0.1 `libmihomo.so` 无法 dlopen：`initial-exec TLS resolves to dynamic definition`。上游 Go c-shared 用 IE TLS，鸿蒙 musl 拒绝。已用 jgowdy/go `non-glibc` 分支（golang/go#75048，GD/TLSDESC）编译工具链（`~/.local/go-gd-src/go`），`MIHOMO_GOROOT` 指向它重编内核；x86_64 模拟器上加载正常
- [-] 0.2 模拟器无法启动 VPN：镜像缺少 `com.huawei.hmos.vpndialog`（VPN 授权组件），`startVpnExtensionAbility` 永不返回。已加 60s 超时并在首页提示；VPN 链路需真机（arm64）验证
- [x] 0.3 真机：arm64 内核已编译（47.9MB，仅 TLSDESC），`abiFilters` 已加 `arm64-v8a`；签名问题是 product 未引用 `signingConfig: "default"`，已修复
- [x] 0.4 真机连上 VPN 但无法上网：gVisor `fdbased.IsSocketFD` 对 VPN fd 调 `fstat` 被鸿蒙拒绝（EACCES），TUN 启动失败后被静默关闭。已把 gvisor 复制到 `core/gvisor` 并在 `go.mod` 用 replace 指向，EACCES/EPERM 时按非 socket 处理
- [x] 0.5 内核日志转发到 hilog（tag `Mihomo`），`hdc hilog` 可直接看内核日志

## 批次 1：Bug 修复（P0）

- [x] 1.1 TUN MTU 与系统 VPN 网卡不一致：内核强制使用与 VpnConfig 相同的 MTU（`core/bridge/main.go`）
- [x] 1.2 连接页 ↑↓ 流量不刷新：ForEach key 只含 id（`views/ConnectionsView.ets`）
- [x] 1.3 VPN 启动失败后扩展不退出，error 状态被 `onDestroy` 的 stopped 覆盖（`vpnability/ClashVpnAbility.ets`）
- [x] 1.4 内核未裁剪：编译加 `no_tailscale,no_zerotier,no_easytier`（`tools/build-core.js`）— 75.4MB → 52.3MB
- [x] 1.5 `.gitignore` 未排除 `entry/libs/`（79MB 二进制）

## 批次 2：性能（P1）

- [ ] 2.1 首页每秒拉全量 `/connections` 且后台不停：改用 `/traffic` WebSocket，页面不可见时暂停
- [ ] 2.2 测速逐节点请求：改用 `/group/{name}/delay`
- [ ] 2.3 代理节点列表、日志列表改 `LazyForEach`；日志批量刷新
- [ ] 2.4 `parseGroups` 在 UI 主线程同步执行：改为异步 NAPI

## 批次 3：构建（P1）

- [x] 3.1 支持 arm64-v8a（真机），`build-core.js all` 一次编双架构
- [x] 3.2 DevEco / Go 路径集中到 `tools/env.js`，可用 `DEVECO_HOME` / `MIHOMO_GOROOT` 覆盖
- [x] 3.3 构建时不再执行 `go mod tidy`
- [-] 3.4 `core/mihomo` 不入库：暂缓。源码仅 6.8MB，随仓库提交更便于复现；GPL 也要求提供对应源码
- [x] 3.5 签名材料移出 `build-profile.json5`，改由 `hvigorfile.ts` 读取被忽略的 `signing.local.json5`
- [x] 3.6 删除一次性调试脚本，补齐中文文档（README、docs/BUILD.md、docs/ARCHITECTURE.md）

## 批次 4：健壮性与安全（P2）

- [ ] 4.1 配置文件原子写入（临时文件 + rename）
- [ ] 4.2 NAPI 参数类型 / `napi_status` 校验，async work 失败不泄漏
- [ ] 4.3 本地 mixed-port 加认证；端口号单一来源（由 ArkTS 传入）
- [ ] 4.4 IPv6：添加 `::/0` 路由或明确阻断，避免绕过 VPN
- [ ] 4.5 远程密钥改用 Asset Store；HTTP 明文时提示

## 批次 5：整洁与功能（P3）

- [ ] 5.1 合并 `importUrl` / `importText` 重复逻辑；SettingsView 只读一次 `Prefs.remote()`
- [ ] 5.2 支持 base64 / 分享链接订阅（Mihomo `common/convert`）
- [ ] 5.3 颜色、文案移入 resources（深色模式、多语言）
- [ ] 5.4 单元测试：Go `applyFilter` / `mirrorGeo` / `MihomoParseGroups`；ArkTS `parseUserInfo` / `nameFromDisposition`

## 变更日志

### 2026-10-14 · 首次发布

- 修复：Go 内核无法在鸿蒙上加载（0.1）、连上 VPN 无法上网（0.4）、签名不生效（0.3）
- 新增：arm64 真机支持、内核日志转发 hilog、VPN 启动 60 秒超时提示
- 构建：路径集中配置、签名材料不入库、内核体积 75.4MB → 47.9MB（arm64）
- 文档：中文 README、编译指南、架构说明
