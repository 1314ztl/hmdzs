import { textToSpeech } from '@kit.CoreSpeechKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SpeechUtil';

/** 朗读状态回调 */
export interface SpeechStateListener {
  onStart?: () => void;
  onFinish?: () => void;
  onStop?: () => void;
  onError?: (err: string) => void;
}

/**
 * 朗读工具:基于 CoreSpeechKit 的文本转语音
 * 支持语速/音调调节、开始/停止
 */
export class SpeechUtil {
  private static engine: textToSpeech.TextToSpeechEngine | null = null;
  private static listener: SpeechStateListener | null = null;
  private static speaking: boolean = false;
  private static requestId: number = 1;

  static isSpeaking(): boolean {
    return SpeechUtil.speaking;
  }

  static setListener(l: SpeechStateListener): void {
    SpeechUtil.listener = l;
  }

  static async init(): Promise<void> {
    if (SpeechUtil.engine !== null) {
      return;
    }
    try {
      const engineParams: textToSpeech.CreateEngineParams = {
        language: 'zh-CN',
        person: 0,
        online: 1,
        extraParams: { 'style': 'interaction-broadcast', 'locate': 'CN', 'name': 'EngineName' } as Record<string, Object>
      };
      SpeechUtil.engine = await textToSpeech.createEngine(engineParams);
      SpeechUtil.engine.setListener({
        onStart: (requestId: string, response: textToSpeech.StartResponse) => {
          SpeechUtil.speaking = true;
          SpeechUtil.listener?.onStart?.();
        },
        onComplete: (requestId: string, response: textToSpeech.CompleteResponse) => {
          SpeechUtil.speaking = false;
          SpeechUtil.listener?.onFinish?.();
        },
        onStop: (requestId: string, response: textToSpeech.StopResponse) => {
          SpeechUtil.speaking = false;
          SpeechUtil.listener?.onStop?.();
        },
        onError: (requestId: string, errorCode: number, errorMessage: string) => {
          SpeechUtil.speaking = false;
          SpeechUtil.listener?.onError?.(`错误码 ${errorCode}: ${errorMessage}`);
        }
      } as textToSpeech.SpeakListener);
    } catch (e) {
      hilog.error(0x0000, TAG, 'createEngine failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 朗读文本
   * @param text 文本
   * @param rate 语速 1-100 → 映射到 0-2 (1 为正常语速)
   * @param pitch 音调 0-2
   */
  static async speak(text: string, rate: number = 50, pitch: number = 1.0): Promise<void> {
    await SpeechUtil.init();
    if (SpeechUtil.engine === null) {
      SpeechUtil.listener?.onError?.('朗读引擎不可用');
      return;
    }
    // 文本过长则截断(单次朗读上限保护)
    const chunk = text.length > 1000 ? text.substring(0, 1000) : text;
    const mappedRate = Math.max(0, Math.min(2, rate / 50));
    try {
      const extra: Record<string, Object> = {
        'speed': mappedRate,
        'pitch': Math.max(0, Math.min(2, pitch)),
        'volume': 1.0
      };
      const speakParams: textToSpeech.SpeakParams = {
        requestId: `req_${SpeechUtil.requestId++}`,
        extraParams: extra
      };
      SpeechUtil.engine.speak(chunk, speakParams);
    } catch (e) {
      hilog.error(0x0000, TAG, 'speak failed: %{public}s', JSON.stringify(e));
      SpeechUtil.listener?.onError?.('朗读失败');
    }
  }

  /**
   * 朗读多段(章节),自动连续
   */
  static async speakSequence(texts: string[], rate: number, pitch: number): Promise<void> {
    await SpeechUtil.init();
    if (texts.length === 0) {
      return;
    }
    SpeechUtil.setListener({
      onFinish: async () => {
        texts.shift();
        if (texts.length > 0 && SpeechUtil.speaking) {
          await SpeechUtil.speak(texts[0], rate, pitch);
        }
      },
      onError: () => {
      }
    });
    await SpeechUtil.speak(texts[0], rate, pitch);
  }

  static async stop(): Promise<void> {
    if (SpeechUtil.engine !== null) {
      try {
        await SpeechUtil.engine.stop();
      } catch (e) {
        // ignore
      }
    }
    SpeechUtil.speaking = false;
  }

  static async shutdown(): Promise<void> {
    if (SpeechUtil.engine !== null) {
      try {
        await SpeechUtil.engine.shutdown();
      } catch (e) {
        // ignore
      }
      SpeechUtil.engine = null;
    }
    SpeechUtil.speaking = false;
  }
}
