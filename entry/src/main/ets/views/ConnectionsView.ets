import { Core } from '../common/Core';
import { ConnItem } from '../common/ClashApi';
import { formatBytes } from '../common/Format';

@Component
export struct ConnectionsView {
  @Link coreUp: boolean;
  @State list: ConnItem[] = [];
  @State filter: string = '';
  private timer: number = -1;

  aboutToAppear(): void {
    this.load();
    this.timer = setInterval(() => { this.load(); }, 2000);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  async load(): Promise<void> {
    if (!this.coreUp) {
      this.list = [];
      return;
    }
    try {
      const snap = await Core.api.connections();
      // Newest first.
      this.list = snap.list.sort((a: ConnItem, b: ConnItem) => b.start.localeCompare(a.start));
    } catch (e) {
      this.list = [];
    }
  }

  host(c: ConnItem): string {
    const h = c.metadata.host.length > 0 ? c.metadata.host : c.metadata.destinationIP;
    return `${h}:${c.metadata.destinationPort}`;
  }

  visible(): ConnItem[] {
    const f = this.filter.trim().toLowerCase();
    if (f.length === 0) {
      return this.list;
    }
    return this.list.filter((c: ConnItem) => this.host(c).toLowerCase().includes(f) ||
      c.chains.join(' ').toLowerCase().includes(f));
  }

  async closeOne(c: ConnItem): Promise<void> {
    try {
      await Core.api.closeConnection(c.id);
      this.load();
    } catch (e) {
      this.toast((e as Error).message);
    }
  }

  async closeAll(): Promise<void> {
    try {
      await Core.api.closeAllConnections();
      this.load();
    } catch (e) {
      this.toast((e as Error).message);
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(`连接 ${this.list.length}`).fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor(['#D93025'])
        }
        .width(36).height(36).backgroundColor('#FCE8E6').enabled(this.list.length > 0)
        .onClick(() => { this.closeAll(); })
      }.width('100%').padding({ left: 16, right: 12, top: 12, bottom: 4 })
      TextInput({ text: this.filter, placeholder: '筛选域名或节点' })
        .margin({ left: 12, right: 12, top: 4 })
        .onChange((v: string) => { this.filter = v; })
      List({ space: 8 }) {
        ForEach(this.visible(), (c: ConnItem) => {
          ListItem() {
            Row({ space: 8 }) {
              Column({ space: 4 }) {
                Text(this.host(c)).fontSize(14).fontWeight(FontWeight.Medium).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${c.metadata.network.toUpperCase()} · ${c.chains.slice().reverse().join(' → ')}`)
                  .fontSize(12).fontColor('#5F6368').maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${c.rule}${c.rulePayload.length > 0 ? '(' + c.rulePayload + ')' : ''} · ↑${formatBytes(c.upload)} ↓${formatBytes(c.download)}`)
                  .fontSize(12).fontColor('#5F6368').maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.xmark')).fontSize(16)
              }.width(30).height(30).backgroundColor('#F1F3F4')
              .onClick(() => { this.closeOne(c); })
            }.padding(12).width('100%').backgroundColor(Color.White).borderRadius(8)
          }
        // Byte counters in the key so rows re-render when traffic changes.
        }, (c: ConnItem) => `${c.id}:${c.upload}:${c.download}`)
      }.padding(12).layoutWeight(1)
    }.width('100%').height('100%')
  }
}
