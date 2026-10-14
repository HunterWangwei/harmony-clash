import { fileIo as fs } from '@kit.CoreFileKit';

export class FileUtil {
  static exists(p: string): boolean {
    return fs.accessSync(p);
  }

  static mkdirs(p: string): void {
    if (!fs.accessSync(p)) {
      fs.mkdirSync(p, true);
    }
  }

  // Writes to a sibling temp file and renames it over the target, so a crash or kill
  // mid-write (e.g. while updating a large subscription) never leaves a truncated file.
  static write(p: string, text: string): void {
    const tmp = `${p}.tmp`;
    const f = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(f.fd, text);
      fs.fsyncSync(f.fd);
    } finally {
      fs.closeSync(f);
    }
    fs.renameSync(tmp, p);
  }

  static read(p: string): string {
    return fs.readTextSync(p);
  }

  static remove(p: string): void {
    if (fs.accessSync(p)) {
      fs.unlinkSync(p);
    }
  }
}
