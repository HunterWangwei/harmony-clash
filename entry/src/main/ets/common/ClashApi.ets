import { http } from '@kit.NetworkKit';
import { ControllerConfig } from './Prefs';

export interface ProxyItem {
  name: string;
  type: string;
  now?: string;
  all?: string[];
  history?: DelayRecord[];
}

export interface DelayRecord {
  time: string;
  delay: number;
}

interface ProxiesResp {
  proxies: Record<string, ProxyItem>;
}

interface VersionResp {
  version: string;
  meta?: boolean;
}

interface ConfigsResp {
  mode: string;
}

interface DelayResp {
  delay: number;
}

interface SelectBody {
  name: string;
}

interface ModeBody {
  mode: string;
}

export interface ConnMeta {
  network: string;
  type: string;
  host: string;
  destinationIP: string;
  destinationPort: string;
}

export interface ConnItem {
  id: string;
  metadata: ConnMeta;
  upload: number;
  download: number;
  start: string;
  chains: string[];
  rule: string;
  rulePayload: string;
}

interface ConnectionsResp {
  downloadTotal: number;
  uploadTotal: number;
  connections?: ConnItem[];
}

export interface ConnSnapshot {
  up: number;
  down: number;
  list: ConnItem[];
}

export interface ProxyGroup {
  name: string;
  type: string;
  now: string;
  all: string[];
}

export interface TrafficSummary {
  up: number;
  down: number;
  count: number;
}

const GROUP_TYPES: string[] = ['Selector', 'URLTest', 'Fallback', 'LoadBalance', 'Relay'];

// Thin wrapper over the Mihomo (Clash Meta) external-controller REST API.
export class ClashApi {
  private cfg: ControllerConfig;
  private delays: Map<string, number> = new Map();

  constructor(cfg: ControllerConfig) {
    this.cfg = cfg;
  }

  private base(): string {
    const scheme = this.cfg.https ? 'https' : 'http';
    return `${scheme}://${this.cfg.host}:${this.cfg.port}`;
  }

  private async request(method: http.RequestMethod, path: string, body?: string): Promise<string> {
    const req = http.createHttp();
    const header: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.cfg.secret.length > 0) {
      header['Authorization'] = `Bearer ${this.cfg.secret}`;
    }
    try {
      const resp = await req.request(this.base() + path, {
        method: method,
        header: header,
        extraData: body,
        connectTimeout: 5000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING
      });
      if (resp.responseCode === 401) {
        throw new Error('密钥错误 (401)');
      }
      if (resp.responseCode >= 400) {
        throw new Error(`HTTP ${resp.responseCode}: ${resp.result as string}`);
      }
      return resp.result as string;
    } finally {
      req.destroy();
    }
  }

  async version(): Promise<string> {
    const v = JSON.parse(await this.request(http.RequestMethod.GET, '/version')) as VersionResp;
    return v.meta ? `Mihomo ${v.version}` : v.version;
  }

  async mode(): Promise<string> {
    const c = JSON.parse(await this.request(http.RequestMethod.GET, '/configs')) as ConfigsResp;
    return c.mode.toLowerCase();
  }

  async setMode(mode: string): Promise<void> {
    const body: ModeBody = { mode: mode };
    await this.request(http.RequestMethod.PATCH, '/configs', JSON.stringify(body));
  }

  async groups(): Promise<ProxyGroup[]> {
    const r = JSON.parse(await this.request(http.RequestMethod.GET, '/proxies')) as ProxiesResp;
    const result: ProxyGroup[] = [];
    const global: ProxyItem | undefined = r.proxies['GLOBAL'];
    // GLOBAL.all preserves the profile's group order; fall back to object order.
    const order: string[] = global?.all ?? Object.keys(r.proxies);
    const names: string[] = ['GLOBAL', ...order];
    const seen: Set<string> = new Set();
    for (const name of names) {
      const p: ProxyItem | undefined = r.proxies[name];
      if (!p || seen.has(name) || !GROUP_TYPES.includes(p.type) || !p.all) {
        continue;
      }
      seen.add(name);
      result.push({ name: p.name, type: p.type, now: p.now ?? '', all: p.all });
    }
    Object.keys(r.proxies).forEach((name: string) => {
      const hist = r.proxies[name].history;
      if (hist && hist.length > 0) {
        this.delays.set(name, hist[hist.length - 1].delay);
      }
    });
    return result;
  }

  cachedDelay(name: string): number | undefined {
    return this.delays.get(name);
  }

  async select(group: string, proxy: string): Promise<void> {
    const body: SelectBody = { name: proxy };
    await this.request(http.RequestMethod.PUT, `/proxies/${encodeURIComponent(group)}`, JSON.stringify(body));
  }

  async delay(proxy: string): Promise<number> {
    const url = encodeURIComponent('https://www.gstatic.com/generate_204');
    try {
      const raw = await this.request(http.RequestMethod.GET,
        `/proxies/${encodeURIComponent(proxy)}/delay?timeout=5000&url=${url}`);
      const d = (JSON.parse(raw) as DelayResp).delay;
      this.delays.set(proxy, d);
      return d;
    } catch (e) {
      this.delays.set(proxy, 0);
      return 0;
    }
  }

  async traffic(): Promise<TrafficSummary> {
    const c = JSON.parse(await this.request(http.RequestMethod.GET, '/connections')) as ConnectionsResp;
    return { up: c.uploadTotal, down: c.downloadTotal, count: c.connections?.length ?? 0 };
  }

  async closeAllConnections(): Promise<void> {
    await this.request(http.RequestMethod.DELETE, '/connections');
  }

  async connections(): Promise<ConnSnapshot> {
    const c = JSON.parse(await this.request(http.RequestMethod.GET, '/connections')) as ConnectionsResp;
    return { up: c.uploadTotal, down: c.downloadTotal, list: c.connections ?? [] };
  }

  async closeConnection(id: string): Promise<void> {
    await this.request(http.RequestMethod.DELETE, `/connections/${encodeURIComponent(id)}`);
  }

  // Mihomo accepts the secret as a query token on WebSocket endpoints.
  logsUrl(level: string): string {
    const scheme = this.cfg.https ? 'wss' : 'ws';
    return `${scheme}://${this.cfg.host}:${this.cfg.port}/logs?level=${level}` +
      `&token=${encodeURIComponent(this.cfg.secret)}`;
  }
}
