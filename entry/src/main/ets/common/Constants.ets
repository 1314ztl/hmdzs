/**
 * 应用常量
 */
export class Constants {
  /** 应用本地存储文件目录名 */
  static readonly BOOKS_DIR: string = 'books';
  /** 阅读设置首选项名称 */
  static readonly PREFS_NAME: string = 'hm_book_prefs';
  /** 书架列表首选项键 */
  static readonly KEY_BOOKSHELF: string = 'bookshelf';
  /** 全局阅读设置键 */
  static readonly KEY_SETTINGS: string = 'read_settings';
  /** 最近阅读书籍 id 键 */
  static readonly KEY_RECENT_BOOK: string = 'recent_book_id';
  /** 单本书籍进度键前缀 */
  static readonly KEY_PROGRESS_PREFIX: string = 'progress_';
  /** 单本书签键前缀 */
  static readonly KEY_BOOKMARKS_PREFIX: string = 'bookmarks_';

  /** 支持的书籍格式 */
  static readonly SUPPORTED_EXT: string[] = ['txt', 'epub'];
  /** 书籍封面默认色板 */
  static readonly COVER_COLORS: string[] = [
    '#8B5E3C', '#5E8B6E', '#6E5E8B', '#8B6E5E', '#5E6E8B', '#A89260'
  ];

  /** 翻页模式 */
  static readonly PAGE_MODE_SCROLL: number = 0;
  static readonly PAGE_MODE_HORIZONTAL: number = 1;

  /** 朗读定时任务最小间隔(分钟)选项 */
  static readonly SLEEP_TIMER_OPTIONS: number[] = [0, 10, 15, 30, 45, 60];

  /** 卡片 action: 打开书籍 */
  static readonly ACTION_OPEN_BOOK: string = 'ohos.bookreader.action.OPEN_BOOK';
  static readonly PARAM_BOOK_ID: string = 'bookId';

  /** 书架排序方式 */
  static readonly SORT_RECENT: number = 0; // 最近阅读
  static readonly SORT_ADDED: number = 1;  // 最近加入
  static readonly SORT_TITLE: number = 2;  // 书名

  /**
   * 根据字符串稳定地挑选一个封面色(FNV-1a 哈希),避免颜色单一
   */
  static pickCoverColor(seed: string): string {
    let hash = 0x811c9dc5;
    for (let i = 0; i < seed.length; i++) {
      hash ^= seed.charCodeAt(i);
      hash = (hash * 0x01000193) >>> 0;
    }
    return Constants.COVER_COLORS[hash % Constants.COVER_COLORS.length];
  }
}

/**
 * 阅读主题
 */
export enum ReadTheme {
  PAPER = 0,   // 羊皮纸
  WHITE = 1,   // 白色
  GREEN = 2,   // 护眼绿
  DARK = 3     // 夜间
}

/**
 * 主题资源映射
 */
export interface ThemeStyle {
  id: ReadTheme;
  name: string;
  bg: Resource;
  text: Resource;
  bgHex: string;
  textHex: string;
}

export class ThemeFactory {
  static readonly THEMES: ThemeStyle[] = [
    { id: ReadTheme.PAPER, name: '羊皮纸', bg: $r('app.color.theme_paper_bg'), text: $r('app.color.theme_paper_text'), bgHex: '#F5EFE0', textHex: '#3A2F24' },
    { id: ReadTheme.WHITE, name: '白色', bg: $r('app.color.theme_white_bg'), text: $r('app.color.theme_white_text'), bgHex: '#FFFFFF', textHex: '#222222' },
    { id: ReadTheme.GREEN, name: '护眼绿', bg: $r('app.color.theme_green_bg'), text: $r('app.color.theme_green_text'), bgHex: '#C7E6C7', textHex: '#244024' },
    { id: ReadTheme.DARK, name: '夜间', bg: $r('app.color.theme_dark_bg'), text: $r('app.color.theme_dark_text'), bgHex: '#1A1A1A', textHex: '#C8C8C8' }
  ];

  static get(themeId: number): ThemeStyle {
    return ThemeFactory.THEMES.find(t => t.id === themeId) ?? ThemeFactory.THEMES[0];
  }
}
