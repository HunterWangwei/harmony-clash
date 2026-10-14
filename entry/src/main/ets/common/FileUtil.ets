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

  static write(p: string, text: string): void {
    const f = fs.openSync(p, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(f.fd, text);
    } finally {
      fs.closeSync(f);
    }
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
