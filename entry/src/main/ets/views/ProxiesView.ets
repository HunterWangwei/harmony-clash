import { Core } from '../common/Core';
import { ProxyGroup } from '../common/ClashApi';
import { delayColor } from '../common/Format';
import { Prefs } from '../common/Prefs';

const PROVIDER_PREFIX: string = '[提供者] ';

@Component
export struct ProxiesView {
  @Link @Watch('onCoreChange') coreUp: boolean;
  @State groups: ProxyGroup[] = [];
  @State expanded: string = '';
  @State testing: string = '';
  @State delayTick: number = 0;
  @State loading: boolean = false;
  @State offline: boolean = true;
  @State errorMsg: string = '';

  aboutToAppear(): void {
    this.load();
  }

  onCoreChange(): void {
    this.load();
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      if (this.coreUp) {
        this.groups = await Core.api.groups();
        this.offline = false;
        return;
      }
    } catch (e) {
      // Fall through to the offline view.
    } finally {
      this.loading = false;
    }
    if (Prefs.remoteEnabled()) {
      this.groups = [];
      this.offline = true;
      this.errorMsg = '无法连接远程控制器';
      return;
    }
    const r = Core.offlineGroups();
    this.groups = r.groups;
    this.offline = true;
    this.errorMsg = r.error;
  }

  async choose(group: ProxyGroup, proxy: string): Promise<void> {
    if (proxy.startsWith(PROVIDER_PREFIX)) {
      this.toast('提供者中的节点需连接后才能加载');
      return;
    }
    if (group.type !== 'Selector') {
      this.toast(`${group.type} 组由内核自动选择`);
      return;
    }
    if (!Prefs.remoteEnabled()) {
      Prefs.setSelection(Prefs.activeId(), group.name, proxy);
    }
    if (this.offline) {
      // Replace the item so the List re-renders the new selection.
      this.groups = this.groups.map((g: ProxyGroup) => {
        if (g.name !== group.name) {
          return g;
        }
        const ng: ProxyGroup = { name: g.name, type: g.type, now: proxy, all: g.all };
        return ng;
      });
      return;
    }
    try {
      await Core.api.select(group.name, proxy);
      this.groups = await Core.api.groups();
    } catch (e) {
      this.toast(`切换失败: ${(e as Error).message}`);
    }
  }

  async testGroup(group: ProxyGroup): Promise<void> {
    if (this.offline) {
      this.toast('测速需要先在首页连接');
      return;
    }
    this.testing = group.name;
    const batch = 8;
    for (let i = 0; i < group.all.length; i += batch) {
      const slice = group.all.slice(i, i + batch);
      await Promise.all(slice.map((p: string) => Core.api.delay(p)));
      this.delayTick++;
    }
    this.testing = '';
  }

  delayLabel(p: string, _tick: number): string {
    if (p.startsWith(PROVIDER_PREFIX)) {
      return '';
    }
    const d = Core.api.cachedDelay(p);
    if (d === undefined) {
      return '--';
    }
    return d === 0 ? '超时' : `${d} ms`;
  }

  @Builder
  GroupCard(group: ProxyGroup) {
    Column() {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(group.name).fontSize(15).fontWeight(FontWeight.Medium).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${group.type} · ${group.now}`).fontSize(12).fontColor('#5F6368').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.testing === group.name) {
          LoadingProgress().width(28).height(28)
        } else {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.average_speed')).fontSize(18)
          }
          .width(32).height(32).backgroundColor('#F1F3F4').enabled(this.testing.length === 0)
          .onClick(() => { this.testGroup(group); })
        }
        SymbolGlyph(this.expanded === group.name ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(18)
      }
      .width('100%').padding(12)
      .onClick(() => { this.expanded = this.expanded === group.name ? '' : group.name; })

      if (this.expanded === group.name) {
        Column() {
          ForEach(group.all, (p: string) => {
            Row() {
              Text(p).fontSize(14).layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(group.now === p ? '#1A73E8' : '#202124')
                .fontWeight(group.now === p ? FontWeight.Medium : FontWeight.Normal)
              Text(this.delayLabel(p, this.delayTick)).fontSize(12)
                .fontColor(delayColor(Core.api.cachedDelay(p)))
            }
            .width('100%').height(44).padding({ left: 12, right: 12 })
            .backgroundColor(group.now === p ? '#E8F0FE' : Color.Transparent)
            .onClick(() => { this.choose(group, p); })
          }, (p: string) => `${group.name}/${p}`)
        }
      }
    }
    .width('100%').backgroundColor(Color.White).borderRadius(8).clip(true)
  }

  build() {
    Column() {
      Row() {
        Text('代理').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        if (this.offline && this.groups.length > 0) {
          Text('未连接 · 选择将在连接后生效').fontSize(12).fontColor('#5F6368').margin({ right: 8 })
        }
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(18)
        }
        .width(36).height(36).backgroundColor('#E8EAED')
        .onClick(() => { this.load(); })
      }.width('100%').padding({ left: 16, right: 12, top: 12, bottom: 4 })

      if (this.groups.length === 0) {
        Text(this.loading ? '加载中' : (this.errorMsg.length > 0 ? this.errorMsg : '配置中没有代理组'))
          .fontSize(14).fontColor('#5F6368').margin({ top: 40, left: 16, right: 16 })
      } else {
        List({ space: 10 }) {
          ForEach(this.groups, (g: ProxyGroup) => {
            ListItem() { this.GroupCard(g) }
          }, (g: ProxyGroup) => `${g.name}:${g.now}`)
        }
        .padding(12).layoutWeight(1)
      }
    }.width('100%').height('100%')
  }
}
