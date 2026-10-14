import { Want } from '@kit.AbilityKit';
import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import bridge from 'libclashbridge.so';
import { FileUtil } from '../common/FileUtil';
import { CONTROLLER_HOST, CONTROLLER_PORT, RUNTIME_FILE, RuntimeConfig, STATE_FILE, TUN_MTU,
  VpnState } from '../common/Runtime';

const TAG = 'ClashVpn';
// Inside Mihomo's default fake-ip range so DNS hijack and TUN addressing agree.
const TUN_ADDR = '198.18.0.1';

export default class ClashVpnAbility extends VpnExtensionAbility {
  private conn: vpnExtension.VpnConnection | null = null;
  // Set when startup fails so onDestroy keeps the error visible to the UI.
  private failed: boolean = false;

  onCreate(want: Want): void {
    hilog.info(0x0000, TAG, 'onCreate');
    this.startVpn().catch((e: Error) => {
      hilog.error(0x0000, TAG, 'start failed: %{public}s', e.message);
      this.failed = true;
      this.writeState('error', e.message ?? String(e));
      this.teardown();
    });
  }

  onDestroy(): void {
    this.teardown();
    if (!this.failed) {
      this.writeState('stopped', '');
    }
  }

  private writeState(state: string, message: string): void {
    const s: VpnState = { state: state, message: message, time: Date.now() };
    try {
      FileUtil.write(`${this.context.filesDir}/${STATE_FILE}`, JSON.stringify(s));
    } catch (e) {
      hilog.error(0x0000, TAG, 'write state failed');
    }
  }

  private async startVpn(): Promise<void> {
    this.writeState('starting', '');
    const rt = JSON.parse(FileUtil.read(`${this.context.filesDir}/${RUNTIME_FILE}`)) as RuntimeConfig;

    this.conn = vpnExtension.createVpnConnection(this.context);
    // Keep the core's own outbound sockets off the VPN to avoid a routing loop.
    await this.conn.protectProcessNet();
    hilog.info(0x0000, TAG, 'protected');

    const config: vpnExtension.VpnConfig = {
      addresses: [{ address: { address: TUN_ADDR, family: 1 }, prefixLength: 30 }],
      routes: [{
        interface: '',
        destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
        gateway: { address: '0.0.0.0', family: 1 },
        hasGateway: false,
        isDefaultRoute: true
      }],
      dnsAddresses: ['198.18.0.2'],
      mtu: TUN_MTU,
      isIPv4Accepted: true,
      isIPv6Accepted: false,
      isBlocking: false,
      blockedApplications: [this.context.applicationInfo.name]
    };
    const fd = await this.conn.create(config);
    hilog.info(0x0000, TAG, 'tun fd %{public}d', fd);

    hilog.info(0x0000, TAG, 'core starting');
    await bridge.start(rt.home, rt.config, `${CONTROLLER_HOST}:${CONTROLLER_PORT}`, rt.secret, fd);
    this.writeState('running', bridge.version());
  }

  private teardown(): void {
    try {
      bridge.stop();
    } catch (e) {
      hilog.error(0x0000, TAG, 'core stop failed');
    }
    if (this.conn) {
      this.conn.destroy().catch(() => {});
      this.conn = null;
    }
  }
}
