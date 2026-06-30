import { Constants, ReadTheme } from '../common/Constants';

/**
 * 书籍数据模型
 */
export interface Book {
  /** 唯一 id */
  id: string;
  /** 书名(去除扩展名) */
  title: string;
  /** 作者,EPUB 可解析,TXT 默认未知 */
  author: string;
  /** 沙箱内相对路径(相对 filesDir) */
  path: string;
  /** 格式: txt | epub */
  format: string;
  /** 文件大小(字节) */
  size: number;
  /** 封面色(本地生成) */
  coverColor: string;
  /** 加入书架时间戳(ms) */
  addedAt: number;
  /** 最近阅读时间戳(ms) */
  lastReadAt: number;
  /** 章节数量 */
  chapterCount: number;
  /** 当前阅读章节索引 */
  chapterIndex: number;
  /** 当前章节内字符偏移 */
  charOffset: number;
  /** 总字符数 */
  totalChars: number;
}

/**
 * 书签
 */
export interface Bookmark {
  /** 书籍 id */
  bookId: string;
  /** 章节索引 */
  chapterIndex: number;
  /** 章节内字符偏移 */
  charOffset: number;
  /** 摘要文本 */
  excerpt: string;
  /** 创建时间(ms) */
  createdAt: number;
}

/**
 * 阅读设置(全局默认 + 可被单本覆盖)
 */
export interface ReadSettings {
  /** 主题 */
  theme: number;
  /** 字号(fp) */
  fontSize: number;
  /** 行距倍率 */
  lineHeight: number;
  /** 段间距倍率 */
  paragraphSpacing: number;
  /** 翻页模式 0=滚动 1=左右 */
  pageMode: number;
  /** 屏幕亮度 0-255,-1 表示跟随系统 */
  brightness: number;
  /** 屏幕常亮 */
  keepScreenOn: boolean;
  /** 朗读语速 1-100 */
  speechRate: number;
  /** 朗读音调 0-2 */
  speechPitch: number;
}

export class ReadSettingsDefaults {
  static create(): ReadSettings {
    return {
      theme: ReadTheme.PAPER,
      fontSize: 18,
      lineHeight: 1.6,
      paragraphSpacing: 1.2,
      pageMode: Constants.PAGE_MODE_SCROLL,
      brightness: -1,
      keepScreenOn: true,
      speechRate: 50,
      speechPitch: 1.0
    } as ReadSettings;
  }
}
