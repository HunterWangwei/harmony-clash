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

- [x] 2.1 首页每秒拉全量 `/connections` 且后台不停：速度和总量改用 `/traffic` WebSocket，连接数 3 秒拉一次，应用退到后台时暂停
- [x] 2.2 测速逐节点请求：改用 `/group/{name}/delay`，一个请求测完整组
- [x] 2.3 日志改 `LazyForEach` + 每 300ms 批量刷新（上限 500 行）；代理组改 `ListItemGroup`，展开的节点按需构建
- [x] 2.4 `parseGroups` 改为异步 NAPI，在工作线程解析

## 批次 3：构建（P1）

- [x] 3.1 支持 arm64-v8a（真机），`build-core.js all` 一次编双架构
- [x] 3.2 DevEco / Go 路径集中到 `tools/env.js`，可用 `DEVECO_HOME` / `MIHOMO_GOROOT` 覆盖
- [x] 3.3 构建时不再执行 `go mod tidy`
- [-] 3.4 `core/mihomo` 不入库：暂缓。源码仅 6.8MB，随仓库提交更便于复现；GPL 也要求提供对应源码
- [x] 3.5 签名材料移出 `build-profile.json5`，改由 `hvigorfile.ts` 读取被忽略的 `signing.local.json5`
- [x] 3.6 删除一次性调试脚本，补齐中文文档（README、docs/BUILD.md、docs/ARCHITECTURE.md）

## 批次 4：健壮性与安全（P2）

- [x] 4.1 配置文件原子写入：写临时文件、fsync 后 rename，更新订阅时被杀也不会留下半截文件
- [x] 4.2 NAPI 校验参数类型并抛 TypeError；创建或排队 async work 失败时释放内存（`QueueWork`）
- [x] 4.3 本地 mixed-port 要求认证（用户 `clash`，密码为控制接口密钥），并清空配置里的 `skip-auth-prefixes`。真机验证：无凭据 407、错误 403、正确 200
- [x] 4.4 IPv6：VPN 增加 IPv6 地址和 `::/0` 路由，`isIPv6Accepted` 改为 true。真机验证 IPv4 照常走隧道；IPv6 默认路由是否生效受系统限制，见架构文档
- [x] 4.5 本机和远程密钥改存 Asset Store（加密、不随备份导出），旧版本存在 preferences 里的密钥首次读取时自动迁移；远程未开 HTTPS 时提示明文传输

## 批次 5：整洁与功能（P3）

- [ ] 5.1 合并 `importUrl` / `importText` 重复逻辑（SettingsView 只读一次 `Prefs.remote()` 已在批次 4 完成）
- [ ] 5.2 支持 base64 / 分享链接订阅（Mihomo `common/convert`）
- [ ] 5.3 颜色、文案移入 resources（深色模式、多语言）
- [ ] 5.4 单元测试：Go `applyFilter` / `mirrorGeo` / `MihomoParseGroups`；ArkTS `parseUserInfo` / `nameFromDisposition`

## 变更日志

版本号在 `AppScope/app.json5`：`versionName` 为 `主.次.修订`，`versionCode` 为 `主×1000000 + 次×1000 + 修订`。应用首页底部和「设置 → 关于」都会显示当前版本和内核版本。

### 1.1.0 · 2026-10-14 · 批次 4：健壮性与安全

- 安全：本地代理端口必须认证；密钥改存系统 Asset Store；远程 HTTP 明文提示
- 健壮性：配置原子写入；NAPI 参数校验和失败清理
- 网络：VPN 同时接管 IPv6
- 新增：首页和设置页显示应用版本、内核版本

### 1.0.0 · 2026-10-14 · 批次 2：性能

- 首页：速度和流量走 `/traffic` WebSocket，轮询从每秒一次全量连接列表降为 3 秒一次只取连接数；应用进入后台时停止轮询和推送
- 代理：分组测速一个请求完成；代理组改用 `ListItemGroup`，展开几百个节点不再卡顿；离线解析配置移到工作线程
- 日志：`LazyForEach` 按需渲染，消息先缓冲再每 300ms 批量刷新，debug 级别下不再卡顿
- 修复：首页统计数字不刷新（`@Builder` 用位置参数传基本类型时不会随状态更新，改为对象参数）
- 修复：日志页在高频日志下崩溃（同一个 `LazyForEach` 数据源混用 `onDataReloaded` 和 `onDatasetChange`，ArkUI 报 401）

### 1.0.0 · 2026-10-14 · 首次发布

- 修复：Go 内核无法在鸿蒙上加载（0.1）、连上 VPN 无法上网（0.4）、签名不生效（0.3）
- 新增：arm64 真机支持、内核日志转发 hilog、VPN 启动 60 秒超时提示
- 构建：路径集中配置、签名材料不入库、内核体积 75.4MB → 47.9MB（arm64）
- 文档：中文 README、编译指南、架构说明
