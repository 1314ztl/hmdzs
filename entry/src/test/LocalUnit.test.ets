import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { TxtParser } from '../main/ets/utils/TxtParser';
import { Constants } from '../main/ets/common/Constants';
import { BookRepository } from '../main/ets/data/BookRepository';
import { Book } from '../main/ets/models/Book';

function makeBook(chapterIndex: number, chapterCount: number, lastReadAt: number): Book {
  return {
    id: 't', title: '测试', author: '', path: '', format: 'txt', size: 0,
    coverColor: '#000000', addedAt: 1, lastReadAt, chapterCount,
    chapterIndex, charOffset: 0, totalChars: 0
  };
}

export default function localUnitTest() {
  describe('localUnitTest', () => {
    beforeAll(() => {});
    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    // TXT 章节切分:识别"第X章"
    it('txt_split_chapters', 0, () => {
      const text = '楔子内容\n第一章 起航\n正文一\n第二章 风波\n正文二';
      const content = TxtParser.splitChapters(text);
      // 至少切出两章(第一章、第二章),外加开头楔子
      expect(content.chapters.length >= 2).assertTrue();
      const hasChapter1 = content.chapters.some(c => c.title.indexOf('第一章') >= 0);
      expect(hasChapter1).assertTrue();
    });

    // TXT 无章节时应回退为单章正文
    it('txt_no_chapter_fallback', 0, () => {
      const content = TxtParser.splitChapters('这是一段没有章节标记的普通文本内容。');
      expect(content.chapters.length).assertEqual(1);
    });

    // 封面配色应稳定且落在色板范围内
    it('cover_color_stable', 0, () => {
      const c1 = Constants.pickCoverColor('abc');
      const c2 = Constants.pickCoverColor('abc');
      expect(c1).assertEqual(c2);
      expect(Constants.COVER_COLORS.indexOf(c1) >= 0).assertTrue();
    });

    // 不同种子应尽量分散(此处仅验证不抛异常且合法)
    it('cover_color_valid', 0, () => {
      const c = Constants.pickCoverColor('another-seed-123');
      expect(c.charAt(0)).assertEqual('#');
    });

    // 进度百分比:未读为 0
    it('progress_unread_zero', 0, () => {
      const b = makeBook(0, 10, 0);
      expect(BookRepository.progressPercent(b)).assertEqual(0);
    });

    // 进度百分比:读到最后一章为 100
    it('progress_last_chapter_full', 0, () => {
      const b = makeBook(9, 10, 123456);
      expect(BookRepository.progressPercent(b)).assertEqual(100);
    });

    // 排序:按书名
    it('sort_by_title', 0, () => {
      const list: Book[] = [makeBook(0, 1, 0), makeBook(0, 1, 0)];
      list[0].title = 'B书';
      list[1].title = 'A书';
      const sorted = BookRepository.sortBooks(list, Constants.SORT_TITLE);
      expect(sorted[0].title).assertEqual('A书');
    });
  });
}
