// Runs the same hvigor assembleHap command DevEco uses and prints the tail of the log.
const { spawnSync } = require('child_process');
const path = require('path');
const root = path.join(__dirname, '..');
const deveco = require('./env').deveco;

// Resolve local file: dependencies (the NAPI type package) before building.
const ohpm = spawnSync('cmd.exe', ['/c', path.join(deveco, 'tools/ohpm/bin/ohpm.bat'), 'install', '--all'], {
  cwd: root,
  encoding: 'utf8'
});
const ohpmOut = (ohpm.stdout || '') + (ohpm.stderr || '');
if (ohpm.status !== 0) {
  console.log(ohpmOut);
  console.log('ohpm install failed', ohpm.status);
  process.exit(1);
}
console.log('ohpm install ok');

const r = spawnSync(path.join(deveco, 'tools/node/node.exe'), [
  path.join(deveco, 'tools/hvigor/bin/hvigorw.js'),
  '--mode', 'module', '-p', 'module=entry@default', '-p', 'product=default',
  '-p', 'requiredDeviceType=phone', 'assembleHap', '--no-daemon'
], {
  cwd: root,
  encoding: 'utf8',
  env: { ...process.env, DEVECO_SDK_HOME: path.join(deveco, 'sdk') }
});
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split(/\r?\n/).filter((l) => !/Finished :entry/.test(l));
console.log(lines.filter((l) => /ERROR|Error Message|At File|BUILD|COMPILE RESULT/.test(l)).join('\n') || lines.slice(-40).join('\n'));
console.log('exit', r.status);
