/**
 * 章节数据结构
 */
export interface Chapter {
  /** 章节标题 */
  title: string;
  /** 章节正文 */
  content: string;
}

/**
 * 解析后的书籍内容
 */
export interface BookContent {
  /** 章节列表 */
  chapters: Chapter[];
  /** 总字符数 */
  totalChars: number;
}
