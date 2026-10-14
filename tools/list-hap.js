// Lists native libs and size of the built HAP (a zip) without extracting it.
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const outDir = path.join(root, 'entry/build/default/outputs/default');
const hap = fs.readdirSync(outDir).find((f) => f.endsWith('.hap'));
if (!hap) {
  console.log('no hap in', outDir);
  process.exit(1);
}
const buf = fs.readFileSync(path.join(outDir, hap));
console.log(hap, `${(buf.length / 1048576).toFixed(1)} MB`);
// Walk the zip central directory.
let eocd = buf.length - 22;
while (eocd >= 0 && buf.readUInt32LE(eocd) !== 0x06054b50) eocd--;
let p = buf.readUInt32LE(eocd + 16);
const n = buf.readUInt16LE(eocd + 10);
for (let i = 0; i < n; i++) {
  const nameLen = buf.readUInt16LE(p + 28);
  const extra = buf.readUInt16LE(p + 30);
  const comment = buf.readUInt16LE(p + 32);
  const size = buf.readUInt32LE(p + 24);
  const name = buf.toString('utf8', p + 46, p + 46 + nameLen);
  if (/^libs\//.test(name)) console.log(' ', name, `${(size / 1048576).toFixed(1)} MB`);
  p += 46 + nameLen + extra + comment;
}
