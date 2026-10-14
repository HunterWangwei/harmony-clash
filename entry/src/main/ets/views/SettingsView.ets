import { AppInfo } from '../common/AppInfo';
import { Core } from '../common/Core';
import { ControllerConfig, Prefs } from '../common/Prefs';
import { CONTROLLER_HOST, CONTROLLER_PORT } from '../common/Runtime';

@Component
export struct SettingsView {
  @State remoteOn: boolean = false;
  @State host: string = '';
  @State portText: string = '';
  @State secret: string = '';
  @State https: boolean = false;

  aboutToAppear(): void {
    // Prefs.remote() parses stored JSON; read it once instead of per field.
    const r = Prefs.remote();
    this.remoteOn = Prefs.remoteEnabled();
    this.host = r.host;
    this.portText = r.port.toString();
    this.secret = r.secret;
    this.https = r.https;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  save(): void {
    const port = Number.parseInt(this.portText);
    if (this.remoteOn && (this.host.trim().length === 0 || Number.isNaN(port) || port <= 0 || port > 65535)) {
      this.toast('请输入有效的地址和端口');
      return;
    }
    const cfg: ControllerConfig = {
      host: this.host.trim(),
      port: Number.isNaN(port) ? 9097 : port,
      secret: this.secret,
      https: this.https
    };
    Prefs.saveRemote(cfg);
    Prefs.setRemoteEnabled(this.remoteOn);
    Core.rebuild();
    this.toast('已保存');
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#5F6368').layoutWeight(1)
      Text(value).fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .copyOption(CopyOptions.LocalDevice)
    }.width('100%').height(32)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('设置').fontSize(20).fontWeight(FontWeight.Medium).width('100%')

        Column({ space: 8 }) {
          Text('本机内核').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
          this.InfoRow('控制接口', `${CONTROLLER_HOST}:${CONTROLLER_PORT}`)
          this.InfoRow('密钥', Prefs.secret())
        }.padding(12).backgroundColor(Color.White).borderRadius(8)

        Column({ space: 10 }) {
          Row() {
            Text('远程控制电脑上的 Clash Verge').fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.remoteOn })
              .onChange((on: boolean) => { this.remoteOn = on; })
          }.width('100%')
          if (this.remoteOn) {
            TextInput({ text: this.host, placeholder: '电脑局域网 IP' })
              .onChange((v: string) => { this.host = v; })
            TextInput({ text: this.portText, placeholder: '端口 (默认 9097)' })
              .type(InputType.Number)
              .onChange((v: string) => { this.portText = v; })
            TextInput({ text: this.secret, placeholder: 'API 密钥' })
              .type(InputType.Password)
              .onChange((v: string) => { this.secret = v; })
            Row() {
              Text('使用 HTTPS').fontSize(14).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.https })
                .onChange((on: boolean) => { this.https = on; })
            }.width('100%')
            if (!this.https) {
              // The secret is sent as a Bearer header (and a query token on WebSockets).
              Text('未使用 HTTPS 时，密钥会以明文在局域网中传输，请只在可信网络中使用')
                .fontSize(12).fontColor('#E37400').width('100%')
            }
          }
          Button('保存').width('100%').height(40).onClick(() => { this.save(); })
        }.padding(12).backgroundColor(Color.White).borderRadius(8)

        Column({ space: 8 }) {
          Text('关于').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
          this.InfoRow('应用版本', AppInfo.appVersion())
          this.InfoRow('内核版本', `Mihomo ${AppInfo.coreVersion()}`)
        }.padding(12).backgroundColor(Color.White).borderRadius(8)
      }.padding(12)
    }.width('100%').height('100%').align(Alignment.Top)
  }
}
