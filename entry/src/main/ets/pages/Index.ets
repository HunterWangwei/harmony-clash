import { HomeView } from '../views/HomeView';
import { ProxiesView } from '../views/ProxiesView';
import { ProfilesView } from '../views/ProfilesView';
import { ConnectionsView } from '../views/ConnectionsView';
import { LogsView } from '../views/LogsView';
import { SettingsView } from '../views/SettingsView';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  // Shared reachability of the controller; HomeView polls and updates it.
  @State coreUp: boolean = false;

  @Builder
  TabItem(icon: Resource, label: string, index: number) {
    Column({ space: 2 }) {
      SymbolGlyph(icon).fontSize(22)
        .fontColor([this.currentTab === index ? '#1A73E8' : '#5F6368'])
      Text(label).fontSize(11).fontColor(this.currentTab === index ? '#1A73E8' : '#5F6368')
    }.width('100%').height(56).justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
      TabContent() { HomeView({ coreUp: $coreUp }) }
        .tabBar(this.TabItem($r('sys.symbol.house'), '首页', 0))
      TabContent() {
        if (this.currentTab === 1) {
          ProxiesView({ coreUp: $coreUp })
        }
      }.tabBar(this.TabItem($r('sys.symbol.paperplane'), '代理', 1))
      TabContent() { ProfilesView() }
        .tabBar(this.TabItem($r('sys.symbol.doc_plaintext'), '订阅', 2))
      TabContent() {
        if (this.currentTab === 3) {
          ConnectionsView({ coreUp: $coreUp })
        }
      }.tabBar(this.TabItem($r('sys.symbol.list_bullet'), '连接', 3))
      TabContent() {
        if (this.currentTab === 4) {
          LogsView({ coreUp: $coreUp })
        }
      }.tabBar(this.TabItem($r('sys.symbol.doc_text'), '日志', 4))
      TabContent() { SettingsView() }
        .tabBar(this.TabItem($r('sys.symbol.gearshape'), '设置', 5))
    }
    .onChange((i: number) => { this.currentTab = i; })
    .backgroundColor('#F1F3F4')
    .width('100%').height('100%')
  }
}
