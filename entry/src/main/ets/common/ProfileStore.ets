import { connection, http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { FileUtil } from './FileUtil';
import { Prefs, Profile } from './Prefs';
import { LOCAL_MIXED_PORT } from './Runtime';

interface UserInfo {
  upload: number;
  download: number;
  total: number;
  expire: number;
}

// Parses "upload=1; download=2; total=3; expire=4" from subscription-userinfo.
function parseUserInfo(v: string): UserInfo {
  const info: UserInfo = { upload: 0, download: 0, total: 0, expire: 0 };
  v.split(';').forEach((part: string) => {
    const kv = part.trim().split('=');
    if (kv.length !== 2) {
      return;
    }
    const n = Number(kv[1]);
    if (Number.isNaN(n)) {
      return;
    }
    if (kv[0] === 'upload') {
      info.upload = n;
    } else if (kv[0] === 'download') {
      info.download = n;
    } else if (kv[0] === 'total') {
      info.total = n;
    } else if (kv[0] === 'expire') {
      info.expire = n;
    }
  });
  return info;
}

function headerValue(headers: Object, name: string): string {
  const rec = headers as Record<string, Object>;
  for (const k of Object.keys(rec)) {
    if (k.toLowerCase() === name) {
      const v = rec[k];
      return Array.isArray(v) ? String((v as Object[])[0]) : String(v);
    }
  }
  return '';
}

// Name from Content-Disposition (filename*=UTF-8''... or filename="...").
function nameFromDisposition(v: string): string {
  const star = /filename\*=UTF-8''([^;]+)/i.exec(v);
  if (star) {
    try {
      return decodeURIComponent(star[1]);
    } catch (e) {
      return star[1];
    }
  }
  const plain = /filename="?([^";]+)"?/i.exec(v);
  return plain ? plain[1] : '';
}

export class ProfileStore {
  static dir(): string {
    return `${Prefs.filesDir}/profiles`;
  }

  static path(id: string): string {
    return `${ProfileStore.dir()}/${id}.yaml`;
  }

  private static async fetchOnce(url: string, viaCore: boolean): Promise<http.HttpResponse> {
    const req = http.createHttp();
    const proxy: connection.HttpProxy = { host: '127.0.0.1', port: LOCAL_MIXED_PORT, exclusionList: [] };
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        // Many providers only return Clash YAML for Clash-like user agents.
        header: { 'User-Agent': 'clash-verge/v2.0.0 mihomo' },
        connectTimeout: 30000,
        readTimeout: 60000,
        usingCache: false,
        // Direct attempts ignore any system proxy; fallback goes through the running core.
        usingProxy: viaCore ? proxy : false,
        expectDataType: http.HttpDataType.STRING
      });
      if (resp.responseCode >= 400) {
        throw new Error(`HTTP ${resp.responseCode}`);
      }
      return resp;
    } finally {
      req.destroy();
    }
  }

  // Direct first (twice), then through the core's local proxy if it is running.
  private static async fetch(url: string): Promise<http.HttpResponse> {
    let last: Error = new Error('下载失败');
    const attempts: boolean[] = [false, false, true];
    for (const viaCore of attempts) {
      try {
        return await ProfileStore.fetchOnce(url, viaCore);
      } catch (e) {
        const err = e as Error;
        last = new Error(err.message ?? String(e));
        // HTTP errors from the provider will not improve by retrying.
        if (/^HTTP \d+/.test(last.message)) {
          throw last;
        }
      }
    }
    throw new Error(`${last.message}（直连与经内核代理均失败，可先粘贴 YAML 导入并连接后再更新）`);
  }

  private static validate(text: string): void {
    if (!/^\s*(proxies|proxy-providers|proxy-groups)\s*:/m.test(text)) {
      throw new Error('内容不是 Clash 配置（缺少 proxies）');
    }
  }

  static async importUrl(url: string, name: string): Promise<Profile> {
    const resp = await ProfileStore.fetch(url);
    const text = resp.result as string;
    ProfileStore.validate(text);
    const info = parseUserInfo(headerValue(resp.header, 'subscription-userinfo'));
    const guessed = nameFromDisposition(headerValue(resp.header, 'content-disposition'));
    const p: Profile = {
      id: util.generateRandomUUID(false).substring(0, 8),
      name: name.trim().length > 0 ? name.trim() : (guessed.length > 0 ? guessed : '订阅'),
      url: url,
      updatedAt: Date.now(),
      upload: info.upload,
      download: info.download,
      total: info.total,
      expire: info.expire
    };
    FileUtil.mkdirs(ProfileStore.dir());
    FileUtil.write(ProfileStore.path(p.id), text);
    const list = Prefs.profiles();
    list.push(p);
    Prefs.saveProfiles(list);
    if (Prefs.activeId().length === 0) {
      Prefs.setActive(p.id);
    }
    return p;
  }

  static importText(text: string, name: string): Profile {
    ProfileStore.validate(text);
    const p: Profile = {
      id: util.generateRandomUUID(false).substring(0, 8),
      name: name.trim().length > 0 ? name.trim() : '本地配置',
      url: '',
      updatedAt: Date.now(),
      upload: 0,
      download: 0,
      total: 0,
      expire: 0
    };
    FileUtil.mkdirs(ProfileStore.dir());
    FileUtil.write(ProfileStore.path(p.id), text);
    const list = Prefs.profiles();
    list.push(p);
    Prefs.saveProfiles(list);
    if (Prefs.activeId().length === 0) {
      Prefs.setActive(p.id);
    }
    return p;
  }

  static async update(id: string): Promise<void> {
    const list = Prefs.profiles();
    const p = list.find((x: Profile) => x.id === id);
    if (!p || p.url.length === 0) {
      return;
    }
    const resp = await ProfileStore.fetch(p.url);
    const text = resp.result as string;
    ProfileStore.validate(text);
    const info = parseUserInfo(headerValue(resp.header, 'subscription-userinfo'));
    FileUtil.write(ProfileStore.path(id), text);
    p.updatedAt = Date.now();
    p.upload = info.upload;
    p.download = info.download;
    p.total = info.total;
    p.expire = info.expire;
    Prefs.saveProfiles(list);
  }

  static remove(id: string): void {
    FileUtil.remove(ProfileStore.path(id));
    Prefs.clearSelections(id);
    const list = Prefs.profiles().filter((x: Profile) => x.id !== id);
    Prefs.saveProfiles(list);
    if (Prefs.activeId() === id) {
      Prefs.setActive(list.length > 0 ? list[0].id : '');
    }
  }
}
