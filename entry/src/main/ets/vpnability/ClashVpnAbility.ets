import { Want } from '@kit.AbilityKit';
import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import bridge from 'libclashbridge.so';
import { FileUtil } from '../common/FileUtil';
import { StatusNotification } from '../common/StatusNotification';
import { CONTROLLER_HOST, CONTROLLER_PORT, RUNTIME_FILE, RuntimeConfig, STATE_FILE, TUN_MTU,
  VpnState } from '../common/Runtime';

const TAG = 'ClashVpn';
// Inside Mihomo's default fake-ip range so DNS hijack and TUN addressing agree.
const TUN_ADDR = '198.18.0.1';
// Mihomo's default TUN IPv6 address. Routing ::/0 into the tunnel keeps IPv6 traffic from
// bypassing the VPN (and leaking the real address) on dual-stack networks.
const TUN_ADDR6 = 'fdfe:dcba:9876::1';
const NOTIFY_MS: number = 1000;

interface CoreStatus {
  up: number;
  down: number;
  node: string;
}

export default class ClashVpnAbility extends VpnExtensionAbility {
  private conn: vpnExtension.VpnConnection | null = null;
  // Set when startup fails so onDestroy keeps the error visible to the UI.
  private failed: boolean = false;
  private notifyTimer: number = -1;

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
      addresses: [
        { address: { address: TUN_ADDR, family: 1 }, prefixLength: 30 },
        { address: { address: TUN_ADDR6, family: 2 }, prefixLength: 126 }
      ],
      routes: [{
        interface: '',
        destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
        gateway: { address: '0.0.0.0', family: 1 },
        hasGateway: false,
        isDefaultRoute: true
      }, {
        interface: '',
        destination: { address: { address: '::', family: 2 }, prefixLength: 0 },
        gateway: { address: '::', family: 2 },
        hasGateway: false,
        isDefaultRoute: true
      }],
      dnsAddresses: ['198.18.0.2'],
      mtu: TUN_MTU,
      isIPv4Accepted: true,
      isIPv6Accepted: true,
      isBlocking: false,
      blockedApplications: [this.context.applicationInfo.name]
    };
    const fd = await this.conn.create(config);
    hilog.info(0x0000, TAG, 'tun fd %{public}d', fd);

    hilog.info(0x0000, TAG, 'core starting');
    await bridge.start(rt.home, rt.config, `${CONTROLLER_HOST}:${CONTROLLER_PORT}`, rt.secret, fd);
    this.writeState('running', bridge.version());
    this.startNotify();
  }

  // This process lives exactly as long as the VPN, so it owns the status notification.
  private startNotify(): void {
    const tick = () => {
      try {
        const st = JSON.parse(bridge.status()) as CoreStatus;
        StatusNotification.showConnected(this.context, st.up, st.down, st.node);
      } catch (e) {
        hilog.warn(0x0000, TAG, 'status failed');
      }
    };
    tick();
    this.notifyTimer = setInterval(tick, NOTIFY_MS);
  }

  private teardown(): void {
    if (this.notifyTimer !== -1) {
      clearInterval(this.notifyTimer);
      this.notifyTimer = -1;
    }
    StatusNotification.showDisconnected(this.context);
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
