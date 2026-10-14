// Runs hdc from the DevEco SDK: node tools/hdc.js [--grep=a,b] <args...>
// --grep keeps only output lines matching any comma-separated pattern (case-insensitive).
const { spawnSync } = require('child_process');
const hdc = require('./env').hdc;
let args = process.argv.slice(2);
let re = null;
if (args.length > 0 && args[0].startsWith('--grep=')) {
  re = new RegExp(args[0].slice(7).split(',').join('|'), 'i');
  args = args.slice(1);
}
const r = spawnSync(hdc, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
let out = ((r.stdout || '') + (r.stderr || '')).trim();
if (re) {
  out = out.split(/\r?\n/).filter((l) => re.test(l)).slice(-80).join('\n');
}
console.log(out);
process.exit(r.status || 0);
