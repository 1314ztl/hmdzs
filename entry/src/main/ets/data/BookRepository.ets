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

/**
 * 书籍仓库:书架管理、内容解析(带缓存)、进度记忆、书签
 */
export class BookRepository {
  private static context: common.Context | null = null;
  private static contentCache: Map<string, BookContent> = new Map();

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
    return await PreferencesUtil.getJson<Book[]>(Constants.KEY_BOOKSHELF, []);
  }

  static async saveBookshelf(books: Book[]): Promise<void> {
    await PreferencesUtil.putJson(Constants.KEY_BOOKSHELF, books);
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
        coverColor: Constants.COVER_COLORS[id.length % Constants.COVER_COLORS.length],
        addedAt: now,
        lastReadAt: 0,
        chapterCount: 0,
        chapterIndex: 0,
        charOffset: 0,
        totalChars: 0
      };
      // 解析以填充章节/字数
      try {
        const content = await BookRepository.parseContent(book);
        book.chapterCount = content.chapters.length;
        book.totalChars = content.totalChars;
        if (f.format === 'epub' && !book.author) {
          book.author = '佚名';
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
  }

  static async updateBook(book: Book): Promise<void> {
    const shelf = await BookRepository.loadBookshelf();
    const idx = shelf.findIndex(b => b.id === book.id);
    if (idx >= 0) {
      shelf[idx] = book;
      await BookRepository.saveBookshelf(shelf);
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
  static async saveProgress(book: Book): Promise<void> {
    book.lastReadAt = Date.now();
    await BookRepository.updateBook(book);
    const progress: ProgressData = {
      chapterIndex: book.chapterIndex,
      charOffset: book.charOffset
    };
    await PreferencesUtil.putJson(Constants.KEY_PROGRESS_PREFIX + book.id, progress);
    await BookRepository.saveRecentBook(book.id);
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
