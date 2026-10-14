// Generates a 216x216 placeholder app icon (solid PNG) without external deps.
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const size = 216;
const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const c = Buffer.alloc(4);
  c.writeUInt32BE(crc(td));
  return Buffer.concat([len, td, c]);
};

// Blue rounded square with a white ring in the middle.
const raw = Buffer.alloc((size * 4 + 1) * size);
for (let y = 0; y < size; y++) {
  raw[y * (size * 4 + 1)] = 0;
  for (let x = 0; x < size; x++) {
    const i = y * (size * 4 + 1) + 1 + x * 4;
    const dx = x - size / 2 + 0.5;
    const dy = y - size / 2 + 0.5;
    const r = Math.sqrt(dx * dx + dy * dy);
    const ring = r > 46 && r < 66;
    raw[i] = ring ? 255 : 26;
    raw[i + 1] = ring ? 255 : 115;
    raw[i + 2] = ring ? 255 : 232;
    raw[i + 3] = 255;
  }
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(size, 0);
ihdr.writeUInt32BE(size, 4);
ihdr[8] = 8;
ihdr[9] = 6;
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', zlib.deflateSync(raw)),
  chunk('IEND', Buffer.alloc(0))
]);

const root = path.join(__dirname, '..');
for (const dir of ['AppScope/resources/base/media', 'entry/src/main/resources/base/media']) {
  fs.mkdirSync(path.join(root, dir), { recursive: true });
  fs.writeFileSync(path.join(root, dir, 'app_icon.png'), png);
}
console.log('icons written');
