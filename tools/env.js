// Shared tool locations. Override with environment variables on machines where DevEco
// Studio or Go live elsewhere.
const os = require('os');
const path = require('path');

const deveco = process.env.DEVECO_HOME || 'D:/DevEco Studio';
const sdk = path.join(deveco, 'sdk/default/openharmony');

module.exports = {
  deveco,
  native: path.join(sdk, 'native'),
  hdc: process.env.HDC || path.join(sdk, 'toolchains/hdc.exe'),
  readelf: path.join(sdk, 'native/llvm/bin/llvm-readelf.exe'),
  // HarmonyOS dlopen rejects Go's default initial-exec TLS, so MIHOMO_GOROOT must point at a
  // toolchain that emits general-dynamic TLS for c-shared (see docs/BUILD.md).
  goRoot: process.env.MIHOMO_GOROOT || path.join(os.homedir(), '.local/go-gd-src/go'),
  goPath: process.env.GOPATH || path.join(os.homedir(), '.local/gopath')
};
