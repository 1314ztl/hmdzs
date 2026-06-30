import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'BackgroundTaskUtil';

/**
 * 后台连续任务工具:支持后台朗读(Speech Kit 在后台持续运行)
 * 通过 AUDIO_PLAYBACK 后台模式,使应用进入后台后朗读不中断
 */
export class BackgroundTaskUtil {
  private static running: boolean = false;
  private static context: common.Context | null = null;

  static isRunning(): boolean {
    return BackgroundTaskUtil.running;
  }

  /**
   * 启动后台连续任务
   */
  static async startBackgroundRunning(context: common.Context, label: string): Promise<boolean> {
    if (BackgroundTaskUtil.running) {
      return true;
    }
    try {
      BackgroundTaskUtil.context = context;
      const ctx = context as common.UIAbilityContext;
      const bundleName = ctx.abilityInfo ? ctx.abilityInfo.bundleName : '';
      const abilityName = ctx.abilityInfo ? ctx.abilityInfo.name : 'EntryAbility';
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: bundleName,
          abilityName: abilityName
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      } as wantAgent.WantAgentInfo;
      const agent: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
      BackgroundTaskUtil.running = true;
      hilog.info(0x0000, TAG, 'background running started: %{public}s', label);
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'startBackgroundRunning failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /**
   * 停止后台连续任务
   */
  static async stopBackgroundRunning(): Promise<void> {
    if (!BackgroundTaskUtil.running || BackgroundTaskUtil.context === null) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(BackgroundTaskUtil.context);
      BackgroundTaskUtil.running = false;
      BackgroundTaskUtil.context = null;
      hilog.info(0x0000, TAG, 'background running stopped');
    } catch (e) {
      hilog.error(0x0000, TAG, 'stopBackgroundRunning failed: %{public}s', JSON.stringify(e));
    }
  }
}
