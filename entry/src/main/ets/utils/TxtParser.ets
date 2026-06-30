import { util } from '@kit.ArkTS';
import { Chapter, BookContent } from '../models/Chapter';

/**
 * TXT 文件解析器:编码识别 + 章节切分
 */
export class TxtParser {
  /** 章节标题正则:匹配 "第X章"/"第X回"/"Chapter X" 等 */
  private static readonly CHAPTER_REGEX: RegExp =
    /^[ \t]*第[\s0-9一二三四五六七八九十百千万零两]{1,7}[章节回卷集部篇话][ \t]*(.*)$/m;

  /**
   * 解码缓冲区,自动识别 UTF-8 / GBK
   */
  static decode(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    // UTF-8 BOM
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      const sub = bytes.subarray(3);
      return util.TextDecoder.create('utf-8').decodeWithStream(sub);
    }
    // GBK BOM (rare) / UTF-16 skipped for simplicity
    // 尝试 UTF-8
    try {
      const utf8Text = util.TextDecoder.create('utf-8').decodeWithStream(bytes);
      if (!TxtParser.hasInvalidUtf8(bytes)) {
        return utf8Text;
      }
    } catch (e) {
      // ignore, fallback below
    }
    // 回退 GBK
    try {
      return util.TextDecoder.create('gbk').decodeWithStream(bytes);
    } catch (e) {
      return util.TextDecoder.create('utf-8').decodeWithStream(bytes);
    }
  }

  /**
   * 粗略判断字节流是否包含非法 UTF-8 序列
   */
  private static hasInvalidUtf8(bytes: Uint8Array): boolean {
    let i = 0;
    while (i < bytes.length) {
      const b = bytes[i];
      let need: number;
      if (b < 0x80) {
        i++;
        continue;
      } else if ((b & 0xE0) === 0xC0) {
        need = 1;
      } else if ((b & 0xF0) === 0xE0) {
        need = 2;
      } else if ((b & 0xF8) === 0xF0) {
        need = 3;
      } else {
        return true;
      }
      for (let j = 1; j <= need; j++) {
        if (i + j >= bytes.length || (bytes[i + j] & 0xC0) !== 0x80) {
          return true;
        }
      }
      i += 1 + need;
    }
    return false;
  }

  /**
   * 将文本切分为章节
   */
  static splitChapters(text: string): BookContent {
    const chapters: Chapter[] = [];
    const lines = text.split(/\r\n|\r|\n/);
    let curTitle = '开始';
    let curLines: string[] = [];
    const push = () => {
      const content = curLines.join('\n').replace(/\n{3,}/g, '\n\n').trim();
      if (content.length > 0 || chapters.length === 0) {
        chapters.push({ title: curTitle, content });
      }
    };

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      const m = line.match(/^[ \t]*(第[\s0-9一二三四五六七八九十百千万零两]{1,7}[章节回卷集部篇话])[ \t]*(.*)$/);
      if (m && m[1]) {
        push();
        curTitle = m[1] + (m[2] ? ' ' + m[2] : '');
        curLines = [];
      } else if (/^[ \t]*(Chapter|CHAPTER|chapter)[ \t]*\d+/.test(line)) {
        push();
        curTitle = line;
        curLines = [];
      } else {
        curLines.push(lines[i]);
      }
    }
    push();

    if (chapters.length === 0) {
      chapters.push({ title: '正文', content: text.trim() });
    }

    let totalChars = 0;
    for (const c of chapters) {
      totalChars += c.content.length;
    }
    return { chapters, totalChars };
  }
}
