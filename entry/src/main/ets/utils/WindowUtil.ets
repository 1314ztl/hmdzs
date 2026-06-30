import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'WindowUtil';

/**
 * 窗口工具:阅读亮度、屏幕常亮
 */
export class WindowUtil {
  /**
   * 设置当前窗口亮度
   * @param brightness 0-255,-1 表示跟随系统(还原为 -1)
   */
  static async setBrightness(context: common.Context, brightness: number): Promise<void> {
    try {
      const win = await window.getLastWindow(context);
      if (brightness < 0) {
        // 跟随系统:设为默认值 -1
        await win.setWindowBrightness(-1);
      } else {
        const v = Math.min(255, Math.max(0, brightness)) / 255;
        await win.setWindowBrightness(v);
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'setBrightness failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 设置屏幕常亮
   */
  static async setKeepScreenOn(context: common.Context, keep: boolean): Promise<void> {
    try {
      const win = await window.getLastWindow(context);
      await win.setWindowKeepScreenOn(keep);
    } catch (e) {
      hilog.error(0x0000, TAG, 'setKeepScreenOn failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 还原亮度为系统默认
   */
  static async resetBrightness(context: common.Context): Promise<void> {
    await WindowUtil.setBrightness(context, -1);
  }
}
