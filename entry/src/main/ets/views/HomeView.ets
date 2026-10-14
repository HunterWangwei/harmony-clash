import { common } from '@kit.AbilityKit';
import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { TrafficFrame } from '../common/ClashApi';
import { Core } from '../common/Core';
import { formatBytes, formatSpeed } from '../common/Format';
import { Prefs, Profile } from '../common/Prefs';
import { FOREGROUND_KEY } from '../common/Runtime';
import { VpnControl } from '../common/VpnControl';

interface StatParam {
  label: string;
  value: string;
}

// Reachability and connection count only; speed and totals arrive over the /traffic socket.
const POLL_MS: number = 3000;

const MODES: string[] = ['rule', 'global', 'direct'];
const MODE_LABELS: string[] = ['规则', '全局', '直连'];

@Component
export struct HomeView {
  @Link coreUp: boolean;
  @State busy: boolean = false;
  @State version: string = '';
  @State mode: string = 'rule';
  @State errorMsg: string = '';
  @State upSpeed: number = 0;
  @State downSpeed: number = 0;
  @State upTotal: number = 0;
  @State downTotal: number = 0;
  @State connCount: number = 0;
  @State profileName: string = '';
  @State remote: boolean = false;
  @StorageProp(FOREGROUND_KEY) @Watch('onForegroundChange') foreground: boolean = true;
  // Failure from the last connect attempt; polling must not clear it.
  private startError: string = '';
  private timer: number = -1;
  private ws: webSocket.WebSocket | null = null;

  aboutToAppear(): void {
    this.resume();
  }

  aboutToDisappear(): void {
    this.pause();
  }

  onForegroundChange(): void {
    if (this.foreground) {
      this.resume();
    } else {
      this.pause();
    }
  }

  private resume(): void {
    if (this.timer !== -1) {
      return;
    }
    this.poll();
    this.timer = setInterval(() => { this.poll(); }, POLL_MS);
  }

  private pause(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.closeTraffic();
  }

  private openTraffic(): void {
    if (this.ws !== null) {
      return;
    }
    const ws = webSocket.createWebSocket();
    ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (err || typeof value !== 'string') {
        return;
      }
      try {
        const f = JSON.parse(value) as TrafficFrame;
        this.upSpeed = f.up;
        this.downSpeed = f.down;
        this.upTotal = f.upTotal;
        this.downTotal = f.downTotal;
      } catch (e) {
        // Ignore malformed frames.
      }
    });
    const drop = () => {
      if (this.ws === ws) {
        this.ws = null;
      }
    };
    ws.on('close', drop);
    ws.on('error', drop);
    this.ws = ws;
    ws.connect(Core.api.trafficUrl()).catch(drop);
  }

  private closeTraffic(): void {
    if (this.ws !== null) {
      this.ws.close().catch(() => {});
      this.ws = null;
    }
    this.upSpeed = 0;
    this.downSpeed = 0;
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  async poll(): Promise<void> {
    const remote = Prefs.remoteEnabled();
    if (remote !== this.remote) {
      // Settings switched controllers; the open socket belongs to the old one.
      this.closeTraffic();
    }
    this.remote = remote;
    const active = Prefs.profiles().find((p: Profile) => p.id === Prefs.activeId());
    this.profileName = active ? active.name : '未选择';
    const wasUp = this.coreUp;
    try {
      if (!this.coreUp || this.version.length === 0) {
        this.version = await Core.api.version();
        this.mode = await Core.api.mode();
      }
      this.connCount = await Core.api.connectionCount();
      this.coreUp = true;
      this.errorMsg = '';
      this.openTraffic();
      if (!wasUp && !this.remote) {
        // Apply nodes picked while disconnected.
        await Core.applySelections();
      }
    } catch (e) {
      this.coreUp = false;
      this.version = '';
      this.closeTraffic();
      if (!this.remote) {
        const st = VpnControl.state(this.ctx());
        this.errorMsg = st && st.state === 'error' ? st.message : this.startError;
      } else {
        this.errorMsg = (e as Error).message ?? '连接失败';
      }
    }
  }

  async toggle(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      if (this.coreUp) {
        await VpnControl.stop(this.ctx());
      } else {
        this.startError = '';
        Core.rebuild();
        // The traffic socket may still point at a previous controller.
        this.closeTraffic();
        await VpnControl.start(this.ctx());
      }
    } catch (e) {
      const msg = (e as Error).message ?? String(e);
      this.startError = msg;
      this.errorMsg = msg;
      this.toast(msg);
    } finally {
      // Give the extension a moment, then poll right away instead of waiting a full interval.
      setTimeout(() => {
        this.busy = false;
        this.poll();
      }, 1500);
    }
  }

  async changeMode(m: string): Promise<void> {
    try {
      await Core.api.setMode(m);
      this.mode = m;
    } catch (e) {
      this.toast(`切换失败: ${(e as Error).message}`);
    }
  }

  // Takes an object so ArkUI passes it by reference and the Text updates when state changes;
  // positional primitive arguments are copied once and never refresh.
  @Builder
  Stat(p: StatParam) {
    Column({ space: 4 }) {
      Text(p.value).fontSize(16).fontWeight(FontWeight.Medium).maxLines(1)
      Text(p.label).fontSize(12).fontColor('#5F6368')
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 14 }) {
          Row({ space: 8 }) {
            Circle({ width: 10, height: 10 }).fill(this.coreUp ? '#188038' : '#9AA0A6')
            Text(this.coreUp ? (this.remote ? `远程 · ${this.version}` : `已连接 · ${this.version}`) : '未连接')
              .fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%')
          if (!this.remote) {
            Button({ type: ButtonType.Circle }) {
              if (this.busy) {
                LoadingProgress().width(40).height(40).color(Color.White)
              } else {
                SymbolGlyph($r('sys.symbol.power')).fontSize(44).fontColor([Color.White])
              }
            }
            .width(96).height(96)
            .backgroundColor(this.coreUp ? '#188038' : '#1A73E8')
            .onClick(() => { this.toggle(); })
            Text(`配置：${this.profileName}`).fontSize(13).fontColor('#5F6368')
          }
          if (this.errorMsg.length > 0) {
            Text(this.errorMsg).fontSize(13).fontColor('#D93025').maxLines(4)
          }
        }
        .padding(16).width('100%').backgroundColor(Color.White).borderRadius(8)

        Row({ space: 4 }) {
          ForEach(MODES, (m: string, i: number) => {
            Text(MODE_LABELS[i])
              .layoutWeight(1).height(34).textAlign(TextAlign.Center).fontSize(14).borderRadius(6)
              .fontColor(this.mode === m ? Color.White : '#202124')
              .backgroundColor(this.mode === m ? '#1A73E8' : Color.Transparent)
              .enabled(this.coreUp)
              .onClick(() => { this.changeMode(m); })
          }, (m: string) => m)
        }
        .padding(4).width('100%').backgroundColor('#E8EAED').borderRadius(8)

        Column({ space: 14 }) {
          Row() {
            this.Stat({ label: '上传速度', value: formatSpeed(this.upSpeed) })
            this.Stat({ label: '下载速度', value: formatSpeed(this.downSpeed) })
          }
          Row() {
            this.Stat({ label: '上传总量', value: formatBytes(this.upTotal) })
            this.Stat({ label: '下载总量', value: formatBytes(this.downTotal) })
          }
          Row() {
            this.Stat({ label: '活动连接', value: this.connCount.toString() })
            this.Stat({ label: '模式', value: this.remote ? '远程控制' : '本机 VPN' })
          }
        }
        .padding(16).width('100%').backgroundColor(Color.White).borderRadius(8)
      }.padding(12)
    }.width('100%').height('100%').align(Alignment.Top)
  }
}
