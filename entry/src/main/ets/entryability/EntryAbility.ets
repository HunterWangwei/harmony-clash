import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Prefs } from '../common/Prefs';
import { Core } from '../common/Core';
import { FOREGROUND_KEY } from '../common/Runtime';

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
      }
    });
  }
}
