import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

export interface ControllerConfig {
  host: string;
  port: number;
  secret: string;
  https: boolean;
}

export interface Profile {
  id: string;
  name: string;
  url: string;
  updatedAt: number;
  upload: number;
  download: number;
  total: number;
  expire: number;
}

// App-wide persisted state (UI process only; the VPN process receives values via Want).
export class Prefs {
  private static store: preferences.Preferences | null = null;
  static filesDir: string = '';

  static init(context: common.UIAbilityContext): void {
    Prefs.store = preferences.getPreferencesSync(context, { name: 'app' });
    Prefs.filesDir = context.filesDir;
  }

  private static getString(key: string, def: string): string {
    return Prefs.store ? Prefs.store.getSync(key, def) as string : def;
  }

  private static putString(key: string, value: string): void {
    if (Prefs.store) {
      Prefs.store.putSync(key, value);
      Prefs.store.flush();
    }
  }

  // Controller secret, generated once. Other apps can reach 127.0.0.1, so it must be random.
  static secret(): string {
    let s = Prefs.getString('secret', '');
    if (s.length === 0) {
      const blob = cryptoFramework.createRandom().generateRandomSync(16);
      s = Array.from(blob.data).map((b: number) => b.toString(16).padStart(2, '0')).join('');
      Prefs.putString('secret', s);
    }
    return s;
  }

  static profiles(): Profile[] {
    try {
      return JSON.parse(Prefs.getString('profiles', '[]')) as Profile[];
    } catch (e) {
      return [];
    }
  }

  static saveProfiles(list: Profile[]): void {
    Prefs.putString('profiles', JSON.stringify(list));
  }

  static activeId(): string {
    return Prefs.getString('active', '');
  }

  static setActive(id: string): void {
    Prefs.putString('active', id);
  }

  // Node choices per profile: { groupName: proxyName }, applied after the core starts.
  static selections(profileId: string): Record<string, string> {
    try {
      return JSON.parse(Prefs.getString(`sel_${profileId}`, '{}')) as Record<string, string>;
    } catch (e) {
      return {};
    }
  }

  static setSelection(profileId: string, group: string, proxy: string): void {
    const sel = Prefs.selections(profileId);
    sel[group] = proxy;
    Prefs.putString(`sel_${profileId}`, JSON.stringify(sel));
  }

  static clearSelections(profileId: string): void {
    if (Prefs.store) {
      Prefs.store.deleteSync(`sel_${profileId}`);
      Prefs.store.flush();
    }
  }

  // Remote mode: control Clash Verge on a PC instead of the on-device core.
  static remoteEnabled(): boolean {
    return Prefs.store ? Prefs.store.getSync('remoteEnabled', false) as boolean : false;
  }

  static setRemoteEnabled(on: boolean): void {
    if (Prefs.store) {
      Prefs.store.putSync('remoteEnabled', on);
      Prefs.store.flush();
    }
  }

  static remote(): ControllerConfig {
    try {
      return JSON.parse(Prefs.getString('remote', '')) as ControllerConfig;
    } catch (e) {
      return { host: '192.168.1.100', port: 9097, secret: '', https: false };
    }
  }

  static saveRemote(cfg: ControllerConfig): void {
    Prefs.putString('remote', JSON.stringify(cfg));
  }
}
