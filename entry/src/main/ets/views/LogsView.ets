import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Core } from '../common/Core';
import { ListSource } from '../common/ListSource';
import { FOREGROUND_KEY } from '../common/Runtime';

interface LogLine {
  type: string;
  payload: string;
}

interface LogRow {
  key: number;
  type: string;
  payload: string;
}

const LEVELS: string[] = ['debug', 'info', 'warning', 'error'];
const MAX_ROWS: number = 500;
// Debug logs can arrive hundreds per second; batch them into one UI update per tick.
const FLUSH_MS: number = 300;

@Component
export struct LogsView {
  @Link coreUp: boolean;
  @State level: string = 'info';
  @State paused: boolean = false;
  @State count: number = 0;
  @StorageProp(FOREGROUND_KEY) @Watch('onForegroundChange') foreground: boolean = true;
  private rows: ListSource<LogRow> = new ListSource<LogRow>();
  private pending: LogRow[] = [];
  private ws: webSocket.WebSocket | null = null;
  private seq: number = 0;
  private timer: number = -1;
  private flushTimer: number = -1;

  aboutToAppear(): void {
    this.start();
  }

  aboutToDisappear(): void {
    this.stop();
  }

  onForegroundChange(): void {
    if (this.foreground) {
      this.start();
    } else {
      this.stop();
    }
  }

  private start(): void {
    if (this.timer !== -1) {
      return;
    }
    this.connect();
    // Reconnect when the core comes up after this view was opened.
    this.timer = setInterval(() => {
      if (this.coreUp && this.ws === null) {
        this.connect();
      }
    }, 2000);
    this.flushTimer = setInterval(() => { this.flush(); }, FLUSH_MS);
  }

  private stop(): void {
    clearInterval(this.timer);
    clearInterval(this.flushTimer);
    this.timer = -1;
    this.flushTimer = -1;
    this.disconnect();
    this.pending = [];
  }

  private flush(): void {
    if (this.pending.length === 0) {
      return;
    }
    // Only the newest MAX_ROWS can survive anyway.
    const batch = this.pending.length > MAX_ROWS ? this.pending.slice(-MAX_ROWS) : this.pending;
    this.pending = [];
    this.rows.append(batch, MAX_ROWS);
    this.count = this.rows.totalCount();
  }

  private clearRows(): void {
    this.pending = [];
    this.rows.clear();
    this.count = 0;
  }

  disconnect(): void {
    if (this.ws) {
      this.ws.close().catch(() => {});
      this.ws = null;
    }
  }

  connect(): void {
    this.disconnect();
    if (!this.coreUp) {
      return;
    }
    const ws = webSocket.createWebSocket();
    ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (err || this.paused || typeof value !== 'string') {
        return;
      }
      try {
        const l = JSON.parse(value) as LogLine;
        this.pending.push({ key: this.seq++, type: l.type, payload: l.payload });
      } catch (e) {
        // Ignore malformed frames.
      }
    });
    ws.on('close', () => {
      if (this.ws === ws) {
        this.ws = null;
      }
    });
    ws.on('error', () => {
      if (this.ws === ws) {
        this.ws = null;
      }
    });
    this.ws = ws;
    ws.connect(Core.api.logsUrl(this.level)).catch(() => {
      if (this.ws === ws) {
        this.ws = null;
      }
    });
  }

  color(t: string): ResourceColor {
    if (t === 'error') {
      return '#D93025';
    }
    if (t === 'warning') {
      return '#E37400';
    }
    return t === 'debug' ? '#9AA0A6' : '#188038';
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(`日志 ${this.count}`).fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.paused ? $r('sys.symbol.play_fill') : $r('sys.symbol.pause'))
            .fontSize(18)
        }.width(36).height(36).backgroundColor('#E8EAED')
        .onClick(() => { this.paused = !this.paused; })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(18)
        }.width(36).height(36).backgroundColor('#E8EAED')
        .onClick(() => { this.clearRows(); })
      }.width('100%').padding({ left: 16, right: 12, top: 12, bottom: 4 })
      Row({ space: 4 }) {
        ForEach(LEVELS, (lv: string) => {
          Text(lv).layoutWeight(1).height(30).textAlign(TextAlign.Center).fontSize(13).borderRadius(6)
            .fontColor(this.level === lv ? Color.White : '#202124')
            .backgroundColor(this.level === lv ? '#1A73E8' : Color.Transparent)
            .onClick(() => {
              this.level = lv;
              this.clearRows();
              this.connect();
            })
        }, (lv: string) => lv)
      }.padding(4).margin({ left: 12, right: 12 }).backgroundColor('#E8EAED').borderRadius(8)
      if (!this.coreUp) {
        Text('内核未运行').fontSize(14).fontColor('#5F6368').margin({ top: 40 })
      }
      List({ space: 4 }) {
        LazyForEach(this.rows, (r: LogRow) => {
          ListItem() {
            Row({ space: 6 }) {
              Text(r.type.substring(0, 4).toUpperCase()).fontSize(11).fontColor(this.color(r.type))
                .width(36).fontFamily('monospace')
              Text(r.payload).fontSize(12).layoutWeight(1).fontFamily('monospace').copyOption(CopyOptions.LocalDevice)
            }.alignItems(VerticalAlign.Top).padding({ top: 4, bottom: 4 })
          }
        }, (r: LogRow) => r.key.toString())
      }
      .cachedCount(10)
      .padding(12).layoutWeight(1).backgroundColor(Color.White).margin(12).borderRadius(8)
    }.width('100%').height('100%')
  }
}
