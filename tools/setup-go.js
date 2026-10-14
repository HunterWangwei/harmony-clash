// Downloads the latest stable Go for windows/amd64 into %USERPROFILE%\.local\go (no system changes).
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const dest = path.join(os.homedir(), '.local');
const goExe = path.join(dest, 'go', 'bin', 'go.exe');
if (fs.existsSync(goExe)) {
  console.log('already installed:', execFileSync(goExe, ['version'], { encoding: 'utf8' }).trim());
  process.exit(0);
}

const list = JSON.parse(execFileSync('curl', ['-sSL', 'https://go.dev/dl/?mode=json'], { encoding: 'utf8' }));
const file = list[0].files.find((f) => f.os === 'windows' && f.arch === 'amd64' && f.kind === 'archive');
console.log('downloading', file.filename, `${(file.size / 1048576).toFixed(0)} MB`);

fs.mkdirSync(dest, { recursive: true });
const zip = path.join(os.tmpdir(), file.filename);
execFileSync('curl', ['-sSL', '-o', zip, `https://go.dev/dl/${file.filename}`], { stdio: 'inherit' });

// Verify checksum before extracting.
const crypto = require('crypto');
const sha = crypto.createHash('sha256').update(fs.readFileSync(zip)).digest('hex');
if (sha !== file.sha256) {
  console.error('checksum mismatch', sha, file.sha256);
  process.exit(1);
}
execFileSync('tar', ['-xf', zip, '-C', dest], { stdio: 'inherit' });
fs.unlinkSync(zip);
console.log('installed:', execFileSync(goExe, ['version'], { encoding: 'utf8' }).trim());
