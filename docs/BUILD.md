# 编译指南

## 环境准备

| 工具 | 说明 |
| --- | --- |
| DevEco Studio | 默认路径 `D:/DevEco Studio`，其他路径用环境变量 `DEVECO_HOME` 指定 |
| Go | 官方 Go 1.27+，仅用于编译下面的补丁版工具链 |
| 补丁版 Go 工具链 | 必需，见下一节 |
| Node.js | 运行 `tools/` 下的脚本，DevEco 自带的也可以 |

### 为什么需要补丁版 Go

官方 Go 编译的 c-shared 库使用 initial-exec TLS，鸿蒙基于 musl 的加载器在 dlopen 时会拒绝：

```
Error relocating libmihomo.so: getgrouplist: initial-exec TLS resolves to dynamic definition
```

上游问题见 [golang/go#54805](https://github.com/golang/go/issues/54805)，目前未修复。本项目使用 [golang/go#75048](https://github.com/golang/go/pull/75048) 的补丁分支，它让 c-shared 改用 TLSDESC（general-dynamic），musl 可以正常加载。

### 编译补丁版工具链

先安装官方 Go（`node tools/setup-go.js` 会装到 `%USERPROFILE%\.local\go`），然后：

```bash
git clone -b non-glibc https://github.com/jgowdy/go.git ~/.local/go-gd-src/go
```

```bash
cd ~/.local/go-gd-src/go/src && GOROOT_BOOTSTRAP="$(cygpath -w ~/.local/go)" cmd.exe //c "$(cygpath -w $PWD)\\make.bat"
```

本项目验证过的提交是 `1a087d05b5cf9573876b18812d8d5516f16bbe57`。工具链默认放在 `~/.local/go-gd-src/go`，其他位置用 `MIHOMO_GOROOT` 指定。

> 在 Git Bash 里直接运行 `make.bat` 可能报"不是内部或外部命令"，这是系统设置了 `NoDefaultCurrentDirectoryInExePath` 导致的，用上面带完整路径的写法即可。

## 编译内核

```bash
node tools/build-core.js all
```

会生成 `entry/libs/arm64-v8a/libmihomo.so` 和 `entry/libs/x86_64/libmihomo.so`，也可以只编一个架构（`arm64` 或 `x86_64`）。编译时用 `no_tailscale,no_zerotier,no_easytier` 去掉了手机用不到的出站，配置里用到这三种出站会解析失败。

检查产物没有静态 TLS（应只有一条 `R_*_TLSDESC`）：

```bash
"D:/DevEco Studio/sdk/default/openharmony/native/llvm/bin/llvm-readelf.exe" -r entry/libs/arm64-v8a/libmihomo.so | grep -i tls
```

## 编译 HAP

```bash
node tools/build.js
```

产物在 `entry/build/default/outputs/default/`。`node tools/list-hap.js` 可以查看 HAP 里的原生库。

## 签名

签名材料与机器绑定，不入库：

1. DevEco Studio → File → Project Structure → Signing Configs，勾选自动签名
2. DevEco 会把签名配置写进 `build-profile.json5` 的 `signingConfigs`。把这个数组剪切到项目根目录的 `signing.local.json5`（已被 git 忽略），`build-profile.json5` 里改回 `"signingConfigs": []`
3. `hvigorfile.ts` 在构建时读取 `signing.local.json5` 注入签名配置；没有这个文件时只生成未签名的 HAP

`build-profile.json5` 的 product 已设置 `"signingConfig": "default"`，名称需要与签名配置一致。

DevEco 每次打开 Signing Configs 或重新签名，都可能把签名配置写回 `build-profile.json5`。克隆后执行一次下面的命令启用提交检查，提交里带有签名材料时会被拒绝：

```bash
git config core.hooksPath .githooks
```

## 安装与调试

`tools/hdc.js` 封装了 SDK 里的 hdc：

```bash
node tools/hdc.js list targets
```

```bash
node tools/hdc.js -t <设备> install -r entry/build/default/outputs/default/entry-default-signed.hap
```

签名换了（比如从未签名包换成签名包）会提示 `sign info inconsistent`，需要先 `uninstall com.example.clashremote`，这会清空应用数据。

查看日志，内核日志的 tag 是 `Mihomo`，VPN 扩展的 tag 是 `ClashVpn`：

```bash
node tools/hdc.js -t <设备> shell "hilog -x" | grep -E "Mihomo|ClashVpn"
```

在电脑上访问手机里的内核 API（密钥在应用「设置」页；本地代理端口 17890 也需要用户 `clash` 加同一个密钥认证）：

```bash
node tools/hdc.js -t <设备> fport tcp:19091 tcp:19090
```

之后请求 `http://127.0.0.1:19091`，带上 `Authorization: Bearer <密钥>`。

## 发布新版本

1. 修改 `AppScope/app.json5` 的 `versionName` 和 `versionCode`（规则见 [OPTIMIZATION.md](../OPTIMIZATION.md#变更日志)），同步 `entry/oh-package.json5` 的 `version`
2. 在 OPTIMIZATION.md 的变更日志里新增一节
3. 重新编译、真机验证后提交，并打 tag：`git tag v<版本号>`

## 更新 Mihomo

```bash
tools\fetch-mihomo.cmd
```

会下载最新版到 `core/mihomo` 并更新 `core/MIHOMO_VERSION`，之后重新编译内核。如果 gVisor 版本变了，需要按 [ARCHITECTURE.md](ARCHITECTURE.md) 重新应用 gVisor 补丁。
