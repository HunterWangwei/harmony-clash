import bridge from 'libclashbridge.so';
import { ClashApi, ProxyGroup } from './ClashApi';
import { ControllerConfig, Prefs } from './Prefs';
import { ProfileStore } from './ProfileStore';
import { CONTROLLER_HOST, CONTROLLER_PORT } from './Runtime';

interface ParsedGroup {
  name: string;
  type: string;
  now: string;
  all: string[];
  use: string[];
}

interface ParseResult {
  groups: ParsedGroup[];
  error: string;
}

export interface OfflineGroups {
  groups: ProxyGroup[];
  error: string;
}

// Holds the API client shared by all views; points at the local core or a remote PC.
export class Core {
  static api: ClashApi = new ClashApi({ host: CONTROLLER_HOST, port: CONTROLLER_PORT, secret: '', https: false });

  static rebuild(): void {
    if (Prefs.remoteEnabled()) {
      Core.api = new ClashApi(Prefs.remote());
    } else {
      const local: ControllerConfig = {
        host: CONTROLLER_HOST,
        port: CONTROLLER_PORT,
        secret: Prefs.secret(),
        https: false
      };
      Core.api = new ClashApi(local);
    }
  }

  // Groups read straight from the active profile while the core is stopped,
  // with saved selections overlaid so the user can pick nodes before connecting.
  static offlineGroups(): OfflineGroups {
    const id = Prefs.activeId();
    if (id.length === 0) {
      return { groups: [], error: '请先在「订阅」中导入并选择一个配置' };
    }
    let parsed: ParseResult;
    try {
      parsed = JSON.parse(bridge.parseGroups(ProfileStore.path(id))) as ParseResult;
    } catch (e) {
      return { groups: [], error: `解析配置失败: ${(e as Error).message}` };
    }
    const sel = Prefs.selections(id);
    const groups: ProxyGroup[] = parsed.groups.map((g: ParsedGroup) => {
      // Provider nodes are only known once the core has fetched them.
      const all = g.all.concat(g.use.map((u: string) => `[提供者] ${u}`));
      const saved = sel[g.name];
      const now = saved !== undefined && g.all.includes(saved) ? saved : g.now;
      const pg: ProxyGroup = { name: g.name, type: g.type, now: now, all: all };
      return pg;
    });
    return { groups: groups, error: parsed.error };
  }

  // Pushes saved selections into a freshly started core.
  static async applySelections(): Promise<void> {
    const id = Prefs.activeId();
    if (id.length === 0 || Prefs.remoteEnabled()) {
      return;
    }
    const sel = Prefs.selections(id);
    let live: ProxyGroup[] = [];
    try {
      live = await Core.api.groups();
    } catch (e) {
      return;
    }
    for (const g of live) {
      const want = sel[g.name];
      if (g.type === 'Selector' && want !== undefined && want !== g.now && g.all.includes(want)) {
        try {
          await Core.api.select(g.name, want);
        } catch (e) {
          // Skip groups the core refuses; the rest still apply.
        }
      }
    }
  }
}
