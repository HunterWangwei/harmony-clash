import { formatBytes, formatDate } from '../common/Format';
import { Prefs, Profile } from '../common/Prefs';
import { ProfileStore } from '../common/ProfileStore';

@Component
export struct ProfilesView {
  @State list: Profile[] = [];
  @State active: string = '';
  @State url: string = '';
  @State name: string = '';
  @State yaml: string = '';
  @State pasteMode: boolean = false;
  @State busy: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  reload(): void {
    this.list = Prefs.profiles();
    this.active = Prefs.activeId();
  }

  async add(): Promise<void> {
    this.busy = 'add';
    try {
      if (this.pasteMode) {
        ProfileStore.importText(this.yaml, this.name);
        this.yaml = '';
      } else {
        const u = this.url.trim();
        if (!/^https?:\/\//.test(u)) {
          throw new Error('请输入 http(s) 订阅链接');
        }
        await ProfileStore.importUrl(u, this.name);
        this.url = '';
      }
      this.name = '';
      this.toast('已导入');
    } catch (e) {
      this.toast(`导入失败: ${(e as Error).message}`);
    } finally {
      this.busy = '';
      this.reload();
    }
  }

  async update(p: Profile): Promise<void> {
    this.busy = p.id;
    try {
      await ProfileStore.update(p.id);
      this.toast('已更新，重新连接后生效');
    } catch (e) {
      this.toast(`更新失败: ${(e as Error).message}`);
    } finally {
      this.busy = '';
      this.reload();
    }
  }

  select(p: Profile): void {
    Prefs.setActive(p.id);
    this.reload();
    this.toast('已选择，重新连接后生效');
  }

  remove(p: Profile): void {
    this.getUIContext().showAlertDialog({
      title: '删除配置',
      message: `确定删除「${p.name}」？`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: '#D93025',
        action: () => {
          ProfileStore.remove(p.id);
          this.reload();
        }
      }
    });
  }

  usage(p: Profile): string {
    if (p.total <= 0) {
      return p.url.length > 0 ? `更新于 ${formatDate(p.updatedAt)}` : '本地配置';
    }
    const used = formatBytes(p.upload + p.download);
    const exp = p.expire > 0 ? ` · 到期 ${formatDate(p.expire * 1000).substring(0, 10)}` : '';
    return `${used} / ${formatBytes(p.total)}${exp}`;
  }

  @Builder
  Item(p: Profile) {
    Row({ space: 8 }) {
      Column({ space: 6 }) {
        Text(p.name).fontSize(15).fontWeight(FontWeight.Medium).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.active === p.id ? '#1A73E8' : '#202124')
        Text(this.usage(p)).fontSize(12).fontColor('#5F6368').maxLines(1)
        if (p.total > 0) {
          Progress({ value: Math.min(p.total, p.upload + p.download), total: p.total, type: ProgressType.Linear })
            .width('100%').color('#1A73E8')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (p.url.length > 0) {
        if (this.busy === p.id) {
          LoadingProgress().width(28).height(28)
        } else {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(18)
          }.width(32).height(32).backgroundColor('#F1F3F4')
          .onClick(() => { this.update(p); })
        }
      }
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor(['#D93025'])
      }.width(32).height(32).backgroundColor('#FCE8E6')
      .onClick(() => { this.remove(p); })
    }
    .padding(12).width('100%').backgroundColor(this.active === p.id ? '#E8F0FE' : Color.White)
    .borderRadius(8)
    .border({ width: this.active === p.id ? 1 : 0, color: '#1A73E8' })
    .onClick(() => { this.select(p); })
  }

  build() {
    Column() {
      Text('订阅').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 4 })
      List({ space: 10 }) {
        ListItem() {
          Column({ space: 10 }) {
            Row({ space: 4 }) {
              Text('链接').layoutWeight(1).height(32).textAlign(TextAlign.Center).fontSize(14).borderRadius(6)
                .fontColor(!this.pasteMode ? Color.White : '#202124')
                .backgroundColor(!this.pasteMode ? '#1A73E8' : Color.Transparent)
                .onClick(() => { this.pasteMode = false; })
              Text('粘贴 YAML').layoutWeight(1).height(32).textAlign(TextAlign.Center).fontSize(14).borderRadius(6)
                .fontColor(this.pasteMode ? Color.White : '#202124')
                .backgroundColor(this.pasteMode ? '#1A73E8' : Color.Transparent)
                .onClick(() => { this.pasteMode = true; })
            }.padding(4).width('100%').backgroundColor('#E8EAED').borderRadius(8)
            if (this.pasteMode) {
              TextArea({ text: this.yaml, placeholder: '粘贴 Clash / Mihomo 配置内容' })
                .height(140).onChange((v: string) => { this.yaml = v; })
            } else {
              TextInput({ text: this.url, placeholder: '订阅链接 https://...' })
                .onChange((v: string) => { this.url = v; })
            }
            TextInput({ text: this.name, placeholder: '名称（可选）' })
              .onChange((v: string) => { this.name = v; })
            Button() {
              if (this.busy === 'add') {
                LoadingProgress().width(24).height(24).color(Color.White)
              } else {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.plus')).fontSize(18).fontColor([Color.White])
                  Text('导入').fontColor(Color.White).fontSize(15)
                }
              }
            }.width('100%').height(40).enabled(this.busy.length === 0)
            .onClick(() => { this.add(); })
          }.padding(12).backgroundColor(Color.White).borderRadius(8)
        }
        ForEach(this.list, (p: Profile) => {
          ListItem() { this.Item(p) }
        }, (p: Profile) => `${p.id}:${p.updatedAt}:${this.active === p.id}`)
      }.padding(12).layoutWeight(1)
    }.width('100%').height('100%')
  }
}
