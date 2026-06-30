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

/**
 * EPUB 解析器:解压 zip → 解析 container/opf → 提取章节文本
 * 说明:EPUB 本质为 zip,通过 zlib 解压后按 spine 顺序提取 xhtml 文本
 */
export class EpubParser {
  /**
   * 解析 EPUB 文件
   * @param epubPath epub 沙箱路径
   */
  static async parse(context: common.Context, epubPath: string): Promise<BookContent> {
    const tempDir = `${context.cacheDir}/epub_${Date.now()}`;
    try {
      if (!fs.accessSync(tempDir)) {
        await fs.mkdir(tempDir);
      }
      await zlib.decompressFile(epubPath, tempDir, { mode: 1 } as zlib.Options);
    } catch (e) {
      hilog.error(0x0000, TAG, 'decompress failed: %{public}s', JSON.stringify(e));
      return { chapters: [{ title: '正文', content: '解析失败' }], totalChars: 4 };
    }

    // 1. container.xml → opf 路径
    const containerPath = `${tempDir}/META-INF/container.xml`;
    const containerXml = await EpubParser.readText(containerPath);
    const opfRel = EpubParser.firstMatch(containerXml, /full-path="([^"]+)"/);
    if (!opfRel) {
      return { chapters: [{ title: '正文', content: '无效的 EPUB' }], totalChars: 7 };
    }
    const opfPath = `${tempDir}/${opfRel}`;
    const opfDir = opfPath.substring(0, opfPath.lastIndexOf('/'));
    const opfXml = await EpubParser.readText(opfPath);

    // 2. manifest: id → {href, mediaType}
    const manifest = new Map<string, ManifestItem>();
    const itemRe = /<item\b[^>]*\bid="([^"]+)"[^>]*\bhref="([^"]+)"[^>]*\bmedia-type="([^"]+)"[^>]*\/?>/g;
    let m: RegExpExecArray | null;
    while ((m = itemRe.exec(opfXml)) !== null) {
      const item: ManifestItem = { href: m[2], mediaType: m[3] };
      manifest.set(m[1], item);
    }

    // 3. spine 顺序
    const idrefs: string[] = [];
    const spineRe = /<itemref\b[^>]*\bidref="([^"]+)"[^>]*\/?>/g;
    while ((m = spineRe.exec(opfXml)) !== null) {
      idrefs.push(m[1]);
    }

    // 4. 元数据:书名/作者(可选,这里仅用于解析内容)
    const chapters: Chapter[] = [];
    let chapterIdx = 0;
    for (const idref of idrefs) {
      const item = manifest.get(idref);
      if (!item || !/x?html/.test(item.mediaType)) {
        continue;
      }
      const htmlPath = `${opfDir}/${decodeURIComponent(item.href)}`;
      let raw: string;
      try {
        raw = await EpubParser.readText(htmlPath);
      } catch (e) {
        continue;
      }
      const title = EpubParser.extractTitle(raw) || `第${chapterIdx + 1}节`;
      const bodyText = EpubParser.stripHtml(raw);
      if (bodyText.trim().length > 0) {
        chapters.push({ title, content: bodyText.trim() });
        chapterIdx++;
      }
    }

    EpubParser.cleanup(tempDir);

    if (chapters.length === 0) {
      chapters.push({ title: '正文', content: '无内容' });
    }
    let totalChars = 0;
    for (const c of chapters) {
      totalChars += c.content.length;
    }
    return { chapters, totalChars };
  }

  private static async readText(path: string): Promise<string> {
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const stat: fs.Stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      const text = util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buf));
      return text;
    } finally {
      fs.closeSync(file);
    }
  }

  private static stripHtml(html: string): string {
    // 取 body 内容
    const bodyMatch = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
    let body = bodyMatch ? bodyMatch[1] : html;
    // 块级标签转换行
    body = body.replace(/<\/(p|div|br|h[1-6]|li|tr)>/gi, '\n');
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
      .replace(/&#(\d+);/g, (_: string, n: string) => String.fromCharCode(parseInt(n, 10)));
    return body;
  }

  private static extractTitle(html: string): string {
    const h = html.match(/<h[1-6][^>]*>([\s\S]*?)<\/h[1-6]>/i);
    if (h && h[1]) {
      return EpubParser.stripHtml(h[1]).trim();
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

  private static cleanup(dir: string): void {
    try {
      fs.rmdirSync(dir);
    } catch (e) {
      // ignore
    }
  }
}
