# Harmony Clash

当前版本：1.1.0（内核 Mihomo v1.19.32）。更新内容见 [OPTIMIZATION.md](OPTIMIZATION.md#变更日志)。

运行在 HarmonyOS NEXT 上的 Clash（Mihomo 内核）客户端，使用 ArkTS 编写界面，通过系统 VPN 扩展接管设备流量。也可以切换到远程模式，控制电脑上的 Clash Verge。

> 本项目仅供学习与研究网络技术使用，请遵守所在地法律法规。

## 功能

- **本机 VPN**：内置 Mihomo v1.19.32 内核，通过 `VpnExtensionAbility` 创建系统 VPN，gVisor 网络栈处理 TUN 流量
- **订阅管理**：链接导入或粘贴 YAML；显示流量用量和到期时间；直连失败时自动经内核代理重试
- **代理组**：未连接时也能浏览和预选节点，连接后自动应用；分组测速
- **模式切换**：规则 / 全局 / 直连
- **连接与日志**：实时连接列表（可筛选、可断开），实时日志（按级别过滤）
- **远程控制**：控制局域网内电脑上的 Clash Verge / Mihomo
- **安全**：控制接口和本地代理都需要密钥，密钥保存在系统 Asset Store
- **版本信息**：首页底部和「设置 → 关于」显示应用版本和内核版本

## 系统要求

| 项目 | 要求 |
| --- | --- |
| 系统 | HarmonyOS NEXT，API 12（5.0.0）及以上 |
| 架构 | arm64-v8a（真机）、x86_64（模拟器） |
| VPN | 需要真机。部分模拟器镜像缺少 VPN 授权组件，无法启动 VPN |

## 快速开始

1. 按 [docs/BUILD.md](docs/BUILD.md) 编译补丁版 Go 工具链和内核
2. 用 DevEco Studio 打开项目，在 Project Structure → Signing Configs 中勾选自动签名
3. 连接真机，点击运行
4. 在「订阅」中导入配置，在「首页」点击连接，首次连接需在系统弹窗中允许 VPN

## 文档

- [docs/BUILD.md](docs/BUILD.md)：环境准备、编译、签名、调试
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：架构设计与关键技术问题
- [OPTIMIZATION.md](OPTIMIZATION.md)：优化记录与路线图

## 目录结构

```
AppScope/              应用级配置（包名、图标）
entry/src/main/
  ets/
    common/            API 客户端、配置存储、订阅、VPN 控制
    views/             各页面（首页、代理、订阅、连接、日志、设置）
    vpnability/        VPN 扩展，承载 Mihomo 内核
  cpp/                 NAPI 桥接层（libclashbridge.so）
core/
  bridge/              Go 导出的 C 接口，编译为 libmihomo.so
  mihomo/              Mihomo 源码（v1.19.32）
  gvisor/              打过补丁的 gVisor（见架构文档）
tools/                 编译与调试脚本
```

## 许可证

本项目以 [GPL-3.0](LICENSE) 发布。内含的 [Mihomo](https://github.com/MetaCubeX/mihomo) 使用 GPL-3.0，[gVisor](https://github.com/google/gvisor) 使用 Apache-2.0。
