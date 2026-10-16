import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { formatSpeed } from './Format';

const TAG = 'ClashNotify';
// One fixed id: the VPN process and the UI process both publish it, so each update replaces
// the previous content instead of stacking notifications.
const NOTIFICATION_ID: number = 1001;
// CONTENT_INFORMATION is LEVEL_MIN: no sound, no banner, no status bar icon, so refreshing
// it every second never disturbs the user.
const SLOT: notificationManager.SlotType = notificationManager.SlotType.CONTENT_INFORMATION;
// Third-party apps cannot make a notification unremovable, so unchanged content is still
// re-published this often to bring it back after the user swipes it away.
const REFRESH_MS: number = 10000;

// The persistent status notification. Tapping it opens EntryAbility.
export class StatusNotification {
  private static agent: WantAgent | null = null;
  private static lastText: string = '';
  private static lastAt: number = 0;

  private static async tapAgent(ctx: common.Context): Promise<WantAgent> {
    if (StatusNotification.agent === null) {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: ctx.applicationInfo.name, abilityName: 'EntryAbility' }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      StatusNotification.agent = await wantAgent.getWantAgent(info);
    }
    return StatusNotification.agent;
  }

  private static async publish(ctx: common.Context, title: string, text: string): Promise<void> {
    const key = `${title}\n${text}`;
    if (key === StatusNotification.lastText) {
      return;
    }
    StatusNotification.lastText = key;
    try {
      const request: notificationManager.NotificationRequest = {
        id: NOTIFICATION_ID,
        notificationSlotType: SLOT,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: title, text: text }
        },
        wantAgent: await StatusNotification.tapAgent(ctx),
        // Keep it after a tap; it only goes away when the user swipes it.
        tapDismissed: false,
        isAlertOnce: true
      };
      await notificationManager.publish(request);
    } catch (e) {
      // Usually the user has turned notifications off for the app.
      hilog.warn(0x0000, TAG, 'publish failed: %{public}s', JSON.stringify(e));
    }
  }

  static showConnected(ctx: common.Context, up: number, down: number, node: string): Promise<void> {
    const where = node.length > 0 ? node : '已连接';
    return StatusNotification.publish(ctx, where, `↑ ${formatSpeed(up)}   ↓ ${formatSpeed(down)}`);
  }

  static showDisconnected(ctx: common.Context): Promise<void> {
    return StatusNotification.publish(ctx, '未连接', '点击打开应用');
  }
}
