import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileUtil } from './FileUtil';
import { Prefs } from './Prefs';
import { ProfileStore } from './ProfileStore';
import { RUNTIME_FILE, RuntimeConfig, STATE_FILE, VPN_ABILITY, VpnState } from './Runtime';

const TAG = 'ClashVpnCtl';
// Long enough for the user to read and accept the first-time consent dialog.
const START_TIMEOUT_MS = 60000;

// UI-side control of the VPN extension that hosts the Mihomo core.
export class VpnControl {
  private static want(context: common.UIAbilityContext): Want {
    return { bundleName: context.applicationInfo.name, abilityName: VPN_ABILITY };
  }

  static async start(context: common.UIAbilityContext): Promise<void> {
    const id = Prefs.activeId();
    if (id.length === 0 || !FileUtil.exists(ProfileStore.path(id))) {
      throw new Error('请先在「订阅」中导入并选择一个配置');
    }
    const home = `${context.filesDir}/mihomo`;
    FileUtil.mkdirs(home);
    const rt: RuntimeConfig = { home: home, config: ProfileStore.path(id), secret: Prefs.secret() };
    FileUtil.write(`${context.filesDir}/${RUNTIME_FILE}`, JSON.stringify(rt));
    // A failed start leaves the extension alive; stop it so onCreate runs again.
    const prev = VpnControl.state(context);
    if (prev !== null && prev.state === 'error') {
      try {
        await VpnControl.stop(context);
      } catch (e) {
        // Already gone.
      }
    }
    FileUtil.remove(`${context.filesDir}/${STATE_FILE}`);
    // The system shows its own VPN consent dialog the first time.
    // Images without the VPN authorization component (com.huawei.hmos.vpndialog, missing on
    // some emulators) never settle this promise, so give up instead of spinning forever.
    let timer = -1;
    const timeout = new Promise<void>((_, reject) => {
      timer = setTimeout(() => {
        reject(new Error('系统未响应 VPN 授权请求（部分模拟器缺少 VPN 授权组件，请在真机上测试）'));
      }, START_TIMEOUT_MS);
    });
    try {
      await Promise.race([vpnExtension.startVpnExtensionAbility(VpnControl.want(context)), timeout]);
    } catch (e) {
      hilog.error(0x0000, TAG, 'startVpnExtensionAbility failed: %{public}s', JSON.stringify(e));
      throw new Error((e as Error).message ?? String(e));
    } finally {
      clearTimeout(timer);
    }
  }

  static async stop(context: common.UIAbilityContext): Promise<void> {
    await vpnExtension.stopVpnExtensionAbility(VpnControl.want(context));
  }

  static state(context: common.UIAbilityContext): VpnState | null {
    const p = `${context.filesDir}/${STATE_FILE}`;
    try {
      return FileUtil.exists(p) ? JSON.parse(FileUtil.read(p)) as VpnState : null;
    } catch (e) {
      return null;
    }
  }
}
