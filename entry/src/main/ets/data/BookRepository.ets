import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, Bookmark, ReadSettings, ReadSettingsDefaults } from '../models/Book';
import { BookContent } from '../models/Chapter';
import { Constants } from '../common/Constants';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { FileScanner, ScannedFile } from '../utils/FileScanner';
import { TxtParser } from '../utils/TxtParser';
import { EpubParser } from '../utils/EpubParser';

const TAG = 'BookRepository';

/** 阅读进度存储结构 */
interface ProgressData {
  chapterIndex: number;
  charOffset: number;
}

/** 书架写盘防抖延时(ms) */
const SHELF_FLUSH_DELAY = 400;

/**
 * 书籍仓库:书架管理、内容解析(带缓存)、进度记忆、书签
 */
export class BookRepository {
  private static context: common.Context | null = null;
  private static contentCache: Map<string, BookContent> = new Map();
  // 内存中的书架快照,进度更新先写内存,再防抖落盘,降低频繁全量写入
  private static shelfCache: Book[] | null = null;
  private static flushTimer: number = -1;
  private static pendingFlush: boolean = false;

  static async init(context: common.Context): Promise<void> {
    if (BookRepository.context === null) {
      BookRepository.context = context;
      await PreferencesUtil.init(context, Constants.PREFS_NAME);
    }
  }

  private static ctx(): common.Context {
    if (BookRepository.context === null) {
      throw new Error('BookRepository not initialized');
    }
    return BookRepository.context;
  }

  // ---------- 书架 ----------
  static async loadBookshelf(): Promise<Book[]> {
    if (BookRepository.shelfCache !== null) {
      return BookRepository.shelfCache;
    }
    const list = await PreferencesUtil.getJson<Book[]>(Constants.KEY_BOOKSHELF, []);
    BookRepository.shelfCache = list;
    return list;
  }

  static async saveBookshelf(books: Book[]): Promise<void> {
    BookRepository.shelfCache = books;
    await PreferencesUtil.putJson(Constants.KEY_BOOKSHELF, books);
  }

  /**
   * 防抖落盘:内存立即生效,延时批量写磁盘,避免频繁 flush 引发卡顿
   */
  private static scheduleShelfFlush(): void {
    BookRepository.pendingFlush = true;
    if (BookRepository.flushTimer !== -1) {
      clearTimeout(BookRepository.flushTimer);
    }
    BookRepository.flushTimer = setTimeout(() => {
      BookRepository.flushShelf();
    }, SHELF_FLUSH_DELAY);
  }

  /** 立即将内存书架写入磁盘 */
  static async flushShelf(): Promise<void> {
    if (BookRepository.flushTimer !== -1) {
      clearTimeout(BookRepository.flushTimer);
      BookRepository.flushTimer = -1;
    }
    if (!BookRepository.pendingFlush || BookRepository.shelfCache === null) {
      return;
    }
    BookRepository.pendingFlush = false;
    await PreferencesUtil.putJson(Constants.KEY_BOOKSHELF, BookRepository.shelfCache);
  }

  /**
   * 将扫描到的文件加入书架(去重)
   */
  static async addScannedFiles(files: ScannedFile[]): Promise<Book[]> {
    const shelf = await BookRepository.loadBookshelf();
    const now = Date.now();
    let added: Book[] = [];
    for (const f of files) {
      // 去重:同路径则跳过
      if (shelf.find(b => b.path === f.path)) {
        continue;
      }
      const id = `${now}_${Math.floor(Math.random() * 100000)}_${added.length}`;
      const book: Book = {
        id,
        title: f.title,
        author: f.format === 'epub' ? '' : '未知',
        path: f.path,
        format: f.format,
        size: f.size,
        coverColor: Constants.pickCoverColor(id + f.title),
        addedAt: now,
        lastReadAt: 0,
        chapterCount: 0,
        chapterIndex: 0,
        charOffset: 0,
        totalChars: 0
      };
      // 解析以填充章节/字数/元数据
      try {
        const content = await BookRepository.parseContent(book);
        book.chapterCount = content.chapters.length;
        book.totalChars = content.totalChars;
        if (f.format === 'epub') {
          const meta = EpubParser.getLastMeta();
          if (meta.title && meta.title.length > 0) {
            book.title = meta.title;
          }
          book.author = (meta.author && meta.author.length > 0) ? meta.author : '佚名';
        }
      } catch (e) {
        hilog.error(0x0000, TAG, 'parse on add failed: %{public}s', JSON.stringify(e));
      }
      shelf.push(book);
      added.push(book);
    }
    await BookRepository.saveBookshelf(shelf);
    return added;
  }

  static async removeBook(book: Book): Promise<void> {
    const shelf = await BookRepository.loadBookshelf();
    const next = shelf.filter(b => b.id !== book.id);
    await BookRepository.saveBookshelf(next);
    FileScanner.removeBookFile(BookRepository.ctx(), book.path);
    BookRepository.contentCache.delete(book.id);
    await PreferencesUtil.delete(Constants.KEY_PROGRESS_PREFIX + book.id);
    await PreferencesUtil.delete(Constants.KEY_BOOKMARKS_PREFIX + book.id);
    // 若删除的是最近阅读书籍,清除记录
    const recent = await BookRepository.getRecentBookId();
    if (recent === book.id) {
      await PreferencesUtil.putString(Constants.KEY_RECENT_BOOK, '');
    }
  }

  /**
   * 按指定方式返回排序后的书架副本
   */
  static sortBooks(books: Book[], sortBy: number): Book[] {
    const arr = books.slice();
    if (sortBy === Constants.SORT_TITLE) {
      arr.sort((a, b) => a.title.localeCompare(b.title, 'zh-Hans-CN'));
    } else if (sortBy === Constants.SORT_ADDED) {
      arr.sort((a, b) => b.addedAt - a.addedAt);
    } else {
      // 最近阅读:有阅读记录的在前,按 lastReadAt 降序,其余按加入时间
      arr.sort((a, b) => {
        if (a.lastReadAt !== b.lastReadAt) {
          return b.lastReadAt - a.lastReadAt;
        }
        return b.addedAt - a.addedAt;
      });
    }
    return arr;
  }

  /** 计算阅读进度百分比(0-100) */
  static progressPercent(book: Book): number {
    if (book.chapterCount <= 0) {
      return 0;
    }
    if (book.lastReadAt <= 0) {
      return 0;
    }
    const p = (book.chapterIndex + 1) / book.chapterCount * 100;
    return Math.min(100, Math.max(0, Math.round(p)));
  }

  static async updateBook(book: Book): Promise<void> {
    const shelf = await BookRepository.loadBookshelf();
    const idx = shelf.findIndex(b => b.id === book.id);
    if (idx >= 0) {
      shelf[idx] = book;
      await BookRepository.saveBookshelf(shelf);
    }
  }

  /** 仅更新内存书架并防抖落盘(用于高频进度更新) */
  private static updateBookDebounced(book: Book): void {
    const shelf = BookRepository.shelfCache;
    if (shelf === null) {
      return;
    }
    const idx = shelf.findIndex(b => b.id === book.id);
    if (idx >= 0) {
      shelf[idx] = book;
      BookRepository.scheduleShelfFlush();
    }
  }

  // ---------- 内容解析 ----------
  static async parseContent(book: Book): Promise<BookContent> {
    const cached = BookRepository.contentCache.get(book.id);
    if (cached) {
      return cached;
    }
    const ctx = BookRepository.ctx();
    let content: BookContent;
    if (book.format === 'txt') {
      const buffer = FileScanner.readBuffer(ctx, book.path);
      const text = TxtParser.decode(buffer);
      content = TxtParser.splitChapters(text);
    } else if (book.format === 'epub') {
      const absPath = `${ctx.filesDir}/${book.path}`;
      content = await EpubParser.parse(ctx, absPath);
    } else {
      content = { chapters: [{ title: '不支持', content: '暂不支持该格式' }], totalChars: 6 };
    }
    BookRepository.contentCache.set(book.id, content);
    return content;
  }

  static clearContentCache(bookId?: string): void {
    if (bookId) {
      BookRepository.contentCache.delete(bookId);
    } else {
      BookRepository.contentCache.clear();
    }
  }

  // ---------- 进度记忆 ----------
  /**
   * 保存阅读进度
   * @param immediate true 时立即落盘(如退出页面);false 时防抖写入(如滚动中)
   */
  static async saveProgress(book: Book, immediate: boolean = true): Promise<void> {
    book.lastReadAt = Date.now();
    const progress: ProgressData = {
      chapterIndex: book.chapterIndex,
      charOffset: book.charOffset
    };
    if (immediate) {
      await BookRepository.updateBook(book);
      await PreferencesUtil.putJson(Constants.KEY_PROGRESS_PREFIX + book.id, progress);
      await BookRepository.saveRecentBook(book.id);
    } else {
      // 高频场景:仅写内存 + 防抖
      BookRepository.updateBookDebounced(book);
      BookRepository.progressCache = progress;
      BookRepository.progressCacheBookId = book.id;
      BookRepository.scheduleProgressFlush(book.id);
    }
  }

  private static progressCache: ProgressData | null = null;
  private static progressCacheBookId: string = '';
  private static progressFlushTimer: number = -1;

  private static scheduleProgressFlush(bookId: string): void {
    if (BookRepository.progressFlushTimer !== -1) {
      clearTimeout(BookRepository.progressFlushTimer);
    }
    BookRepository.progressFlushTimer = setTimeout(() => {
      BookRepository.flushProgress(bookId);
    }, SHELF_FLUSH_DELAY);
  }

  /** 将缓存的进度写入磁盘 */
  static async flushProgress(bookId: string): Promise<void> {
    if (BookRepository.progressFlushTimer !== -1) {
      clearTimeout(BookRepository.progressFlushTimer);
      BookRepository.progressFlushTimer = -1;
    }
    if (BookRepository.progressCache === null || BookRepository.progressCacheBookId !== bookId) {
      return;
    }
    await PreferencesUtil.putJson(Constants.KEY_PROGRESS_PREFIX + bookId, BookRepository.progressCache);
    await BookRepository.saveRecentBook(bookId);
    await BookRepository.flushShelf();
  }

  static async loadProgress(book: Book): Promise<Book> {
    const def: ProgressData = { chapterIndex: 0, charOffset: 0 };
    const p = await PreferencesUtil.getJson<ProgressData>(
      Constants.KEY_PROGRESS_PREFIX + book.id,
      def
    );
    book.chapterIndex = p.chapterIndex ?? 0;
    book.charOffset = p.charOffset ?? 0;
    return book;
  }

  // ---------- 最近阅读 ----------
  static async saveRecentBook(bookId: string): Promise<void> {
    await PreferencesUtil.putString(Constants.KEY_RECENT_BOOK, bookId);
  }

  static async getRecentBookId(): Promise<string> {
    return await PreferencesUtil.getString(Constants.KEY_RECENT_BOOK, '');
  }

  static async getRecentBook(): Promise<Book | null> {
    const id = await BookRepository.getRecentBookId();
    if (!id) {
      return null;
    }
    const shelf = await BookRepository.loadBookshelf();
    return shelf.find(b => b.id === id) ?? null;
  }

  // ---------- 书签 ----------
  static async loadBookmarks(bookId: string): Promise<Bookmark[]> {
    return await PreferencesUtil.getJson<Bookmark[]>(Constants.KEY_BOOKMARKS_PREFIX + bookId, []);
  }

  static async saveBookmarks(bookId: string, marks: Bookmark[]): Promise<void> {
    await PreferencesUtil.putJson(Constants.KEY_BOOKMARKS_PREFIX + bookId, marks);
  }

  static async addBookmark(mark: Bookmark): Promise<Bookmark[]> {
    const marks = await BookRepository.loadBookmarks(mark.bookId);
    // 同位置去重
    if (!marks.find(m => m.chapterIndex === mark.chapterIndex && m.charOffset === mark.charOffset)) {
      marks.push(mark);
      marks.sort((a, b) => a.chapterIndex - b.chapterIndex || a.charOffset - b.charOffset);
      await BookRepository.saveBookmarks(mark.bookId, marks);
    }
    return marks;
  }

  static async removeBookmark(bookId: string, mark: Bookmark): Promise<Bookmark[]> {
    let marks = await BookRepository.loadBookmarks(bookId);
    marks = marks.filter(m => !(m.chapterIndex === mark.chapterIndex && m.charOffset === mark.charOffset));
    await BookRepository.saveBookmarks(bookId, marks);
    return marks;
  }

  // ---------- 全局设置 ----------
  static async loadSettings(): Promise<ReadSettings> {
    const def = ReadSettingsDefaults.create();
    const s = await PreferencesUtil.getJson<ReadSettings>(Constants.KEY_SETTINGS, def);
    return {
      theme: s.theme ?? def.theme,
      fontSize: s.fontSize ?? def.fontSize,
      lineHeight: s.lineHeight ?? def.lineHeight,
      paragraphSpacing: s.paragraphSpacing ?? def.paragraphSpacing,
      pageMode: s.pageMode ?? def.pageMode,
      brightness: s.brightness ?? def.brightness,
      keepScreenOn: s.keepScreenOn ?? def.keepScreenOn,
      speechRate: s.speechRate ?? def.speechRate,
      speechPitch: s.speechPitch ?? def.speechPitch
    } as ReadSettings;
  }

  static async saveSettings(settings: ReadSettings): Promise<void> {
    await PreferencesUtil.putJson(Constants.KEY_SETTINGS, settings);
  }
}
