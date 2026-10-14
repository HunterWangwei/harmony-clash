import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Core } from '../common/Core';

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
const MAX_ROWS: number = 300;

@Component
export struct LogsView {
  @Link coreUp: boolean;
  @State rows: LogRow[] = [];
  @State level: string = 'info';
  @State paused: boolean = false;
  private ws: webSocket.WebSocket | null = null;
  private seq: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.connect();
    // Reconnect when the core comes up after this view was opened.
    this.timer = setInterval(() => {
      if (this.coreUp && this.ws === null) {
        this.connect();
      }
    }, 2000);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
    this.disconnect();
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
        const next = this.rows.slice(Math.max(0, this.rows.length - MAX_ROWS + 1));
        next.push({ key: this.seq++, type: l.type, payload: l.payload });
        this.rows = next;
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
        Text('日志').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.paused ? $r('sys.symbol.play_fill') : $r('sys.symbol.pause'))
            .fontSize(18)
        }.width(36).height(36).backgroundColor('#E8EAED')
        .onClick(() => { this.paused = !this.paused; })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(18)
        }.width(36).height(36).backgroundColor('#E8EAED')
        .onClick(() => { this.rows = []; })
      }.width('100%').padding({ left: 16, right: 12, top: 12, bottom: 4 })
      Row({ space: 4 }) {
        ForEach(LEVELS, (lv: string) => {
          Text(lv).layoutWeight(1).height(30).textAlign(TextAlign.Center).fontSize(13).borderRadius(6)
            .fontColor(this.level === lv ? Color.White : '#202124')
            .backgroundColor(this.level === lv ? '#1A73E8' : Color.Transparent)
            .onClick(() => {
              this.level = lv;
              this.connect();
            })
        }, (lv: string) => lv)
      }.padding(4).margin({ left: 12, right: 12 }).backgroundColor('#E8EAED').borderRadius(8)
      if (!this.coreUp) {
        Text('内核未运行').fontSize(14).fontColor('#5F6368').margin({ top: 40 })
      }
      List({ space: 4 }) {
        ForEach(this.rows, (r: LogRow) => {
          ListItem() {
            Row({ space: 6 }) {
              Text(r.type.substring(0, 4).toUpperCase()).fontSize(11).fontColor(this.color(r.type))
                .width(36).fontFamily('monospace')
              Text(r.payload).fontSize(12).layoutWeight(1).fontFamily('monospace').copyOption(CopyOptions.LocalDevice)
            }.alignItems(VerticalAlign.Top).padding({ top: 4, bottom: 4 })
          }
        }, (r: LogRow) => r.key.toString())
      }
      .padding(12).layoutWeight(1).backgroundColor(Color.White).margin(12).borderRadius(8)
    }.width('100%').height('100%')
  }
}
