import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'PreferencesUtil';

/**
 * 首选项存储工具:保存书架、阅读设置、进度、书签
 */
export class PreferencesUtil {
  private static prefs: preferences.Preferences | null = null;

  static async init(context: common.Context, name: string): Promise<void> {
    if (PreferencesUtil.prefs === null) {
      PreferencesUtil.prefs = await preferences.getPreferences(context, name);
    }
  }

  static async put(key: string, value: preferences.ValueType): Promise<void> {
    if (PreferencesUtil.prefs === null) {
      hilog.error(0x0000, TAG, 'prefs not initialized');
      return;
    }
    await PreferencesUtil.prefs.put(key, value);
    await PreferencesUtil.prefs.flush();
  }

  static async get(key: string, def: preferences.ValueType): Promise<preferences.ValueType> {
    if (PreferencesUtil.prefs === null) {
      return def;
    }
    return await PreferencesUtil.prefs.get(key, def);
  }

  static async putString(key: string, value: string): Promise<void> {
    await PreferencesUtil.put(key, value);
  }

  static async getString(key: string, def: string): Promise<string> {
    const v = await PreferencesUtil.get(key, def);
    return (v as string) ?? def;
  }

  static async putJson(key: string, obj: object): Promise<void> {
    await PreferencesUtil.putString(key, JSON.stringify(obj));
  }

  static async getJson<T>(key: string, def: T): Promise<T> {
    const raw = await PreferencesUtil.getString(key, '');
    if (!raw) {
      return def;
    }
    try {
      return JSON.parse(raw) as T;
    } catch (e) {
      hilog.error(0x0000, TAG, 'parse json failed: %{public}s', JSON.stringify(e));
      return def;
    }
  }

  static async has(key: string): Promise<boolean> {
    if (PreferencesUtil.prefs === null) {
      return false;
    }
    return await PreferencesUtil.prefs.has(key);
  }

  static async delete(key: string): Promise<void> {
    if (PreferencesUtil.prefs === null) {
      return;
    }
    await PreferencesUtil.prefs.delete(key);
    await PreferencesUtil.prefs.flush();
  }
}
