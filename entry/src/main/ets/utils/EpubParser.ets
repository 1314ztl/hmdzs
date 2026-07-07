import { zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Chapter, BookContent } from '../models/Chapter';

const TAG = 'EpubParser';

/** EPUB manifest 项 */
interface ManifestItem {
  href: string;
  mediaType: string;
}

/** EPUB 元数据(书名/作者) */
export interface EpubMeta {
  title: string;
  author: string;
}

/**
 * EPUB 解析器:解压 zip → 解析 container/opf → 提取章节文本
 * 说明:EPUB 本质为 zip,通过 zlib 解压后按 spine 顺序提取 xhtml 文本
 */
export class EpubParser {
  /** 最近一次解析得到的元数据(供 BookRepository 读取书名/作者) */
  private static lastMeta: EpubMeta = { title: '', author: '' };

  static getLastMeta(): EpubMeta {
    return { title: EpubParser.lastMeta.title, author: EpubParser.lastMeta.author };
  }

  /**
   * 解析 EPUB 文件
   * @param epubPath epub 沙箱路径
   */
  static async parse(context: common.Context, epubPath: string): Promise<BookContent> {
    EpubParser.lastMeta = { title: '', author: '' };
    const tempDir = `${context.cacheDir}/epub_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    try {
      if (!fs.accessSync(tempDir)) {
        fs.mkdirSync(tempDir);
      }
      await zlib.decompressFile(epubPath, tempDir, { mode: 1 } as zlib.Options);
      const result = await EpubParser.parseFromDir(tempDir);
      return result;
    } catch (e) {
      hilog.error(0x0000, TAG, 'parse failed: %{public}s', JSON.stringify(e));
      return EpubParser.fallback('解析失败,请确认文件是否为有效的 EPUB');
    } finally {
      EpubParser.cleanup(tempDir);
    }
  }

  private static async parseFromDir(tempDir: string): Promise<BookContent> {
    // 1. container.xml → opf 路径
    const containerPath = `${tempDir}/META-INF/container.xml`;
    const containerXml = await EpubParser.readText(containerPath);
    const opfRel = EpubParser.firstMatch(containerXml, /full-path="([^"]+)"/);
    if (!opfRel) {
      return EpubParser.fallback('无效的 EPUB(缺少 OPF)');
    }
    const opfPath = `${tempDir}/${opfRel}`;
    const opfDir = opfPath.substring(0, opfPath.lastIndexOf('/'));
    const opfXml = await EpubParser.readText(opfPath);

    // 2. 元数据:书名/作者
    EpubParser.lastMeta = {
      title: EpubParser.extractMeta(opfXml, 'title'),
      author: EpubParser.extractMeta(opfXml, 'creator')
    };

    // 3. manifest: id → {href, mediaType}
    const manifest = new Map<string, ManifestItem>();
    const itemRe = /<item\b[^>]*\/?>/g;
    let tag: RegExpExecArray | null;
    while ((tag = itemRe.exec(opfXml)) !== null) {
      const seg = tag[0];
      const id = EpubParser.attr(seg, 'id');
      const href = EpubParser.attr(seg, 'href');
      const mediaType = EpubParser.attr(seg, 'media-type');
      if (id && href) {
        manifest.set(id, { href, mediaType });
      }
    }

    // 4. spine 顺序
    const idrefs: string[] = [];
    const spineRe = /<itemref\b[^>]*\/?>/g;
    while ((tag = spineRe.exec(opfXml)) !== null) {
      const idref = EpubParser.attr(tag[0], 'idref');
      if (idref) {
        idrefs.push(idref);
      }
    }

    // 5. 逐章提取文本
    const chapters: Chapter[] = [];
    let chapterIdx = 0;
    for (const idref of idrefs) {
      const item = manifest.get(idref);
      if (!item || !/x?html/.test(item.mediaType)) {
        continue;
      }
      const htmlPath = `${opfDir}/${EpubParser.safeDecode(item.href)}`;
      let raw: string;
      try {
        raw = await EpubParser.readText(htmlPath);
      } catch (e) {
        continue;
      }
      const title = EpubParser.extractTitle(raw) || `第 ${chapterIdx + 1} 节`;
      const bodyText = EpubParser.stripHtml(raw);
      if (bodyText.trim().length > 0) {
        chapters.push({ title, content: bodyText.trim() });
        chapterIdx++;
      }
    }

    if (chapters.length === 0) {
      return EpubParser.fallback('未能提取到正文内容');
    }
    let totalChars = 0;
    for (const c of chapters) {
      totalChars += c.content.length;
    }
    return { chapters, totalChars };
  }

  private static fallback(msg: string): BookContent {
    return { chapters: [{ title: '正文', content: msg }], totalChars: msg.length };
  }

  private static async readText(path: string): Promise<string> {
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const stat: fs.Stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buf));
    } finally {
      fs.closeSync(file);
    }
  }

  /** 提取单个标签的属性值 */
  private static attr(tagSeg: string, name: string): string {
    const re = new RegExp(`\\b${name}\\s*=\\s*"([^"]*)"`);
    const m = tagSeg.match(re);
    if (m && m[1]) {
      return m[1];
    }
    const re2 = new RegExp(`\\b${name}\\s*=\\s*'([^']*)'`);
    const m2 = tagSeg.match(re2);
    return m2 && m2[1] ? m2[1] : '';
  }

  /** 提取 dc:title / dc:creator 元数据 */
  private static extractMeta(opfXml: string, tag: string): string {
    const re = new RegExp(`<dc:${tag}[^>]*>([\\s\\S]*?)</dc:${tag}>`, 'i');
    const m = opfXml.match(re);
    if (m && m[1]) {
      return EpubParser.stripHtml(m[1]).trim();
    }
    return '';
  }

  private static safeDecode(s: string): string {
    try {
      return decodeURIComponent(s);
    } catch (e) {
      return s;
    }
  }

  private static stripHtml(html: string): string {
    // 取 body 内容
    const bodyMatch = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
    let body = bodyMatch ? bodyMatch[1] : html;
    // 移除 script/style
    body = body.replace(/<script[\s\S]*?<\/script>/gi, '');
    body = body.replace(/<style[\s\S]*?<\/style>/gi, '');
    // 块级标签转换行
    body = body.replace(/<\/(p|div|h[1-6]|li|tr|section|article)>/gi, '\n');
    body = body.replace(/<br\s*\/?>/gi, '\n');
    // 去除所有标签
    body = body.replace(/<[^>]+>/g, '');
    // 解码常见实体
    body = body
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#(\d+);/g, (_: string, n: string) => String.fromCharCode(parseInt(n, 10)))
      .replace(/&#x([0-9a-fA-F]+);/g, (_: string, n: string) => String.fromCharCode(parseInt(n, 16)));
    return body;
  }

  private static extractTitle(html: string): string {
    const h = html.match(/<h[1-6][^>]*>([\s\S]*?)<\/h[1-6]>/i);
    if (h && h[1]) {
      const t = EpubParser.stripHtml(h[1]).trim();
      if (t.length > 0) {
        return t;
      }
    }
    const t = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    if (t && t[1]) {
      return EpubParser.stripHtml(t[1]).trim();
    }
    return '';
  }

  private static firstMatch(src: string, re: RegExp): string | null {
    const m = src.match(re);
    return m && m[1] ? m[1] : null;
  }

  /** 递归删除临时目录(zlib 解压产生多级目录,rmdir 对非空目录会失败) */
  private static cleanup(dir: string): void {
    try {
      if (fs.accessSync(dir)) {
        // rmdirSync 在 HarmonyOS 上支持递归删除目录及其内容
        fs.rmdirSync(dir);
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'cleanup failed: %{public}s', JSON.stringify(e));
    }
  }
}
