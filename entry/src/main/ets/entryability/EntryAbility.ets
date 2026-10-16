import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { notificationManager } from '@kit.NotificationKit';
import { Prefs } from '../common/Prefs';
import { Core } from '../common/Core';
import { FOREGROUND_KEY } from '../common/Runtime';
import { StatusNotification } from '../common/StatusNotification';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Prefs.init(this.context);
    Core.rebuild();
  }

  // Views watch this to stop polling and sockets while the app is in the background.
  onForeground(): void {
    AppStorage.setOrCreate<boolean>(FOREGROUND_KEY, true);
  }

  onBackground(): void {
    AppStorage.setOrCreate<boolean>(FOREGROUND_KEY, false);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'ClashRemote', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      this.setupNotification();
    });
  }

  // Asks for notification permission once (the system remembers the answer), then shows the
  // disconnected state unless the core is up, in which case the VPN process owns the content.
  private async setupNotification(): Promise<void> {
    try {
      if (!notificationManager.isNotificationEnabledSync()) {
        await notificationManager.requestEnableNotification(this.context);
      }
    } catch (e) {
      // Declined, or the dialog is already open.
      return;
    }
    // Ask the core itself: vpn_state.json can still say "running" after a crash.
    try {
      await Core.api.version();
    } catch (e) {
      StatusNotification.showDisconnected(this.context);
    }
  }
}
