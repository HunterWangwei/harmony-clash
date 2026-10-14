// Cross-compiles core/bridge into libmihomo.so for HarmonyOS using the DevEco OHOS clang.
// Usage: node tools/build-core.js [x86_64|arm64|all]   (default x86_64 for the emulator)
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const arch = process.argv[2] || 'x86_64';
const targets = {
  x86_64: { goarch: 'amd64', triple: 'x86_64-linux-ohos', abi: 'x86_64' },
  arm64: { goarch: 'arm64', triple: 'aarch64-linux-ohos', abi: 'arm64-v8a' }
};
const t = targets[arch];
if (arch === 'all') {
  for (const a of Object.keys(targets)) {
    const r = spawnSync(process.execPath, [__filename, a], { stdio: 'inherit' });
    if (r.status !== 0) process.exit(r.status || 1);
  }
  process.exit(0);
}
if (!t) {
  console.error('unknown arch', arch);
  process.exit(1);
}

const paths = require('./env');

const root = path.join(__dirname, '..');
const native = paths.native;
const clang = path.join(native, 'llvm/bin/clang.exe').replace(/\\/g, '/');
const sysroot = path.join(native, 'sysroot').replace(/\\/g, '/');
const goRoot = paths.goRoot;
const goExe = path.join(goRoot, 'bin/go.exe');
if (!fs.existsSync(goExe)) {
  console.error(`Go toolchain not found at ${goRoot}; set MIHOMO_GOROOT (see docs/BUILD.md)`);
  process.exit(1);
}
const outDir = path.join(root, 'entry/libs', t.abi);
fs.mkdirSync(outDir, { recursive: true });

// Go splits CC into fields and only honors quotes at the start of a field,
// so each argument containing a space must be quoted as a whole.
const cc = `"${clang}" --target=${t.triple} "--sysroot=${sysroot}"`;
const env = {
  ...process.env,
  GOROOT: goRoot,
  GOPATH: paths.goPath,
  GOPROXY: 'https://goproxy.cn,https://proxy.golang.org,direct',
  GOSUMDB: 'sum.golang.google.cn',
  GOOS: 'linux',
  GOARCH: t.goarch,
  CGO_ENABLED: '1',
  CC: cc,
  CGO_CFLAGS: '-O2 -fPIC',
  CGO_LDFLAGS: '-Wl,-soname,libmihomo.so'
};

function run(args, cwd) {
  console.log('> go', args.join(' '));
  const r = spawnSync(goExe, args, { cwd, env, stdio: 'inherit' });
  if (r.status !== 0) {
    process.exit(r.status || 1);
  }
}

const bridge = path.join(root, 'core/bridge');
const version = fs.readFileSync(path.join(root, 'core/MIHOMO_VERSION'), 'utf8').trim();
run([
  // Drop the large mesh-VPN outbounds that a phone client does not need.
  'build', '-trimpath', '-buildmode=c-shared', '-tags', 'with_gvisor,no_tailscale,no_zerotier,no_easytier',
  '-ldflags', `-s -w -X github.com/metacubex/mihomo/constant.Version=${version}`,
  '-o', path.join(outDir, 'libmihomo.so'), '.'
], bridge);

// The generated header is only needed by the NAPI layer; move it next to the C++ sources.
const header = path.join(outDir, 'libmihomo.h');
const cppInc = path.join(root, 'entry/src/main/cpp/include');
fs.mkdirSync(cppInc, { recursive: true });
if (fs.existsSync(header)) {
  fs.renameSync(header, path.join(cppInc, 'libmihomo.h'));
}
const size = fs.statSync(path.join(outDir, 'libmihomo.so')).size;
console.log(`built ${t.abi}/libmihomo.so (${(size / 1048576).toFixed(1)} MB)`);
