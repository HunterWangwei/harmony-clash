import { bundleManager } from '@kit.AbilityKit';
import bridge from 'libclashbridge.so';

// Version strings shown in the UI. Read once from the installed bundle and the bundled
// core, so they always match AppScope/app.json5 and core/MIHOMO_VERSION.
export class AppInfo {
  private static app: string = '';
  private static core: string = '';

  // e.g. "1.1.0 (1001000)"
  static appVersion(): string {
    if (AppInfo.app.length === 0) {
      try {
        const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
        AppInfo.app = `${info.versionName} (${info.versionCode})`;
      } catch (e) {
        AppInfo.app = '未知';
      }
    }
    return AppInfo.app;
  }

  // Version compiled into libmihomo.so, e.g. "v1.19.32"; available even when the core is stopped.
  static coreVersion(): string {
    if (AppInfo.core.length === 0) {
      try {
        AppInfo.core = bridge.version();
      } catch (e) {
        AppInfo.core = '未知';
      }
    }
    return AppInfo.core;
  }
}
