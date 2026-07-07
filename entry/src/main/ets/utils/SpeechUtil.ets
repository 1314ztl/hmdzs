import { textToSpeech } from '@kit.CoreSpeechKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SpeechUtil';

/** 朗读状态回调 */
export interface SpeechStateListener {
  /** 整段(章节)文本朗读完成 */
  onFinish?: () => void;
  /** 手动停止 */
  onStop?: () => void;
  /** 出错 */
  onError?: (err: string) => void;
}

/**
 * 朗读工具:基于 CoreSpeechKit 的文本转语音
 * 特性:
 *  - 单例引擎 + 单例底层监听器,避免多处 setListener 竞态
 *  - 长章节自动分句成多个片段串行朗读,不再截断到 1000 字
 *  - 支持语速/音调调节、开始/停止
 */
export class SpeechUtil {
  private static engine: textToSpeech.TextToSpeechEngine | null = null;
  private static listener: SpeechStateListener | null = null;
  private static speaking: boolean = false;
  private static requestSeq: number = 1;

  // 分段朗读队列状态
  private static queue: string[] = [];
  private static queueIndex: number = 0;
  private static curRate: number = 50;
  private static curPitch: number = 1.0;
  // 单次片段最大字符数(引擎单次朗读上限保护)
  private static readonly MAX_CHUNK: number = 500;

  static isSpeaking(): boolean {
    return SpeechUtil.speaking;
  }

  static setListener(l: SpeechStateListener | null): void {
    SpeechUtil.listener = l;
  }

  static async init(): Promise<boolean> {
    if (SpeechUtil.engine !== null) {
      return true;
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
        },
        onComplete: (requestId: string, response: textToSpeech.CompleteResponse) => {
          // 当前片段完成 → 播放下一片段;全部完成才回调 onFinish
          SpeechUtil.onChunkComplete();
        },
        onStop: (requestId: string, response: textToSpeech.StopResponse) => {
          SpeechUtil.speaking = false;
        },
        onError: (requestId: string, errorCode: number, errorMessage: string) => {
          SpeechUtil.speaking = false;
          SpeechUtil.queue = [];
          SpeechUtil.queueIndex = 0;
          SpeechUtil.listener?.onError?.(`错误码 ${errorCode}: ${errorMessage}`);
        }
      } as textToSpeech.SpeakListener);
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'createEngine failed: %{public}s', JSON.stringify(e));
      SpeechUtil.engine = null;
      return false;
    }
  }

  /**
   * 朗读整段文本(自动分句串行朗读完整内容)
   * @param text 文本(可为整章)
   * @param rate 语速 1-100 → 映射到 0-2 (50 为正常语速)
   * @param pitch 音调 0-2
   */
  static async speak(text: string, rate: number = 50, pitch: number = 1.0): Promise<void> {
    const ok = await SpeechUtil.init();
    if (!ok || SpeechUtil.engine === null) {
      SpeechUtil.listener?.onError?.('朗读引擎不可用');
      return;
    }
    // 先停止已有朗读,重置队列
    await SpeechUtil.stopInternal();
    SpeechUtil.queue = SpeechUtil.splitIntoChunks(text);
    SpeechUtil.queueIndex = 0;
    SpeechUtil.curRate = rate;
    SpeechUtil.curPitch = pitch;
    if (SpeechUtil.queue.length === 0) {
      SpeechUtil.listener?.onFinish?.();
      return;
    }
    SpeechUtil.speaking = true;
    SpeechUtil.speakCurrentChunk();
  }

  /** 播放当前队列片段 */
  private static speakCurrentChunk(): void {
    if (SpeechUtil.engine === null || SpeechUtil.queueIndex >= SpeechUtil.queue.length) {
      return;
    }
    const chunk = SpeechUtil.queue[SpeechUtil.queueIndex];
    const mappedRate = Math.max(0, Math.min(2, SpeechUtil.curRate / 50));
    try {
      const extra: Record<string, Object> = {
        'speed': mappedRate,
        'pitch': Math.max(0, Math.min(2, SpeechUtil.curPitch)),
        'volume': 1.0
      };
      const speakParams: textToSpeech.SpeakParams = {
        requestId: `req_${SpeechUtil.requestSeq++}`,
        extraParams: extra
      };
      SpeechUtil.engine.speak(chunk, speakParams);
    } catch (e) {
      hilog.error(0x0000, TAG, 'speak failed: %{public}s', JSON.stringify(e));
      SpeechUtil.listener?.onError?.('朗读失败');
    }
  }

  /** 片段完成回调:推进队列或结束 */
  private static onChunkComplete(): void {
    if (!SpeechUtil.speaking) {
      return;
    }
    SpeechUtil.queueIndex++;
    if (SpeechUtil.queueIndex < SpeechUtil.queue.length) {
      SpeechUtil.speakCurrentChunk();
    } else {
      // 整段朗读结束
      SpeechUtil.speaking = false;
      SpeechUtil.queue = [];
      SpeechUtil.queueIndex = 0;
      SpeechUtil.listener?.onFinish?.();
    }
  }

  /**
   * 将长文本按句子/长度切分为多个可朗读片段
   */
  private static splitIntoChunks(text: string): string[] {
    const normalized = text.replace(/\s+/g, ' ').trim();
    if (normalized.length === 0) {
      return [];
    }
    // 按句末标点断句(不依赖 lookbehind,兼容性更好)
    const sentences = SpeechUtil.splitSentences(normalized);
    const chunks: string[] = [];
    let buffer = '';
    for (const s of sentences) {
      if (buffer.length + s.length > SpeechUtil.MAX_CHUNK) {
        if (buffer.length > 0) {
          chunks.push(buffer);
          buffer = '';
        }
        // 单句超长时硬切
        if (s.length > SpeechUtil.MAX_CHUNK) {
          for (let i = 0; i < s.length; i += SpeechUtil.MAX_CHUNK) {
            chunks.push(s.substring(i, i + SpeechUtil.MAX_CHUNK));
          }
        } else {
          buffer = s;
        }
      } else {
        buffer += s;
      }
    }
    if (buffer.length > 0) {
      chunks.push(buffer);
    }
    return chunks;
  }

  /** 手动按句末标点断句,保留标点 */
  private static splitSentences(text: string): string[] {
    const enders = '。！？；.!?;';
    const result: string[] = [];
    let cur = '';
    for (let i = 0; i < text.length; i++) {
      const c = text.charAt(i);
      cur += c;
      if (enders.indexOf(c) >= 0) {
        result.push(cur);
        cur = '';
      }
    }
    if (cur.length > 0) {
      result.push(cur);
    }
    return result;
  }

  /** 内部停止,不清空外部监听器 */
  private static async stopInternal(): Promise<void> {
    SpeechUtil.speaking = false;
    SpeechUtil.queue = [];
    SpeechUtil.queueIndex = 0;
    if (SpeechUtil.engine !== null) {
      try {
        await SpeechUtil.engine.stop();
      } catch (e) {
        // ignore
      }
    }
  }

  static async stop(): Promise<void> {
    await SpeechUtil.stopInternal();
  }

  static async shutdown(): Promise<void> {
    await SpeechUtil.stopInternal();
    if (SpeechUtil.engine !== null) {
      try {
        await SpeechUtil.engine.shutdown();
      } catch (e) {
        // ignore
      }
      SpeechUtil.engine = null;
    }
    SpeechUtil.listener = null;
  }
}
