import { common } from '@kit.AbilityKit';
import { Book, Bookmark } from '../models/Book';
import { BookRepository } from '../data/BookRepository';
import { BookContent, Chapter } from '../models/Chapter';
import { BookCover } from '../components/BookCover';
import { NavRouter } from '../common/NavRouter';

/**
 * 书籍详情页:书籍信息、继续阅读、章节目录、书签管理
 */
@Component
export struct BookDetailPage {
  @State book: Book | null = null;
  @State content: BookContent | null = null;
  @State bookmarks: Bookmark[] = [];
  @State tab: number = 0; // 0 目录 1 书签

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.Context;
    await BookRepository.init(ctx);
    const id = AppStorage.get<string>('detailBookId') ?? '';
    const shelf = await BookRepository.loadBookshelf();
    const found = shelf.find(b => b.id === id);
    if (found) {
      this.book = await BookRepository.loadProgress(found);
      this.content = await BookRepository.parseContent(this.book as Book);
      this.bookmarks = await BookRepository.loadBookmarks(id);
    }
  }

  private readAt(chapterIndex: number, charOffset: number = 0): void {
    if (this.book === null) {
      return;
    }
    (this.book as Book).chapterIndex = chapterIndex;
    (this.book as Book).charOffset = charOffset;
    BookRepository.saveProgress(this.book as Book);
    AppStorage.setOrCreate<string>('readerBookId', (this.book as Book).id);
    NavRouter.push('reader');
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 12 }) {
        Text('‹')
          .fontSize(30)
          .fontColor($r('app.color.theme_paper_text'))
          .onClick(() => NavRouter.pop())
        Text('书籍详情')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.theme_paper_text'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.shelf_bg'))

      if (this.book !== null) {
        // 头部信息
        Row({ space: 16 }) {
          BookCover({ book: this.book as Book })
            .width(90)
            .height(125)
          Column({ space: 6 }) {
            Text((this.book as Book).title)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.theme_paper_text'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`作者:${(this.book as Book).author || '佚名'}`)
              .fontSize(13)
              .fontColor('rgba(58,47,36,0.7)')
            Text(`格式:${(this.book as Book).format.toUpperCase()}  ·  ${(this.book as Book).chapterCount} 章`)
              .fontSize(12)
              .fontColor('rgba(58,47,36,0.5)')
            Text(`大小:${this.formatSize((this.book as Book).size)}`)
              .fontSize(12)
              .fontColor('rgba(58,47,36,0.5)')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')

        // 操作按钮
        Row({ space: 12 }) {
          Button('继续阅读')
            .type(ButtonType.Capsule)
            .backgroundColor($r('app.color.primary'))
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .onClick(() => this.readAt((this.book as Book).chapterIndex, (this.book as Book).charOffset))
          Button('从头开始')
            .type(ButtonType.Capsule)
            .backgroundColor('rgba(139,94,60,0.12)')
            .fontColor($r('app.color.primary'))
            .layoutWeight(1)
            .onClick(() => this.readAt(0, 0))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })

        // Tab
        Row() {
          Text(`目录(${this.content ? this.content.chapters.length : 0})`)
            .fontSize(14)
            .fontColor(this.tab === 0 ? $r('app.color.primary') : 'rgba(58,47,36,0.6)')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 10, bottom: 10 })
            .border({ width: { bottom: 2 }, color: { bottom: this.tab === 0 ? $r('app.color.primary') : 'transparent' } })
            .onClick(() => this.tab = 0)
          Text(`书签(${this.bookmarks.length})`)
            .fontSize(14)
            .fontColor(this.tab === 1 ? $r('app.color.primary') : 'rgba(58,47,36,0.6)')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 10, bottom: 10 })
            .border({ width: { bottom: 2 }, color: { bottom: this.tab === 1 ? $r('app.color.primary') : 'transparent' } })
            .onClick(() => this.tab = 1)
        }
        .width('100%')
        .backgroundColor('#FFFFFF')

        // 列表
        if (this.tab === 0) {
          this.ChapterList()
        } else {
          this.BookmarkList()
        }
      } else {
        Column() {
          LoadingProgress().width(40).height(40)
          Text('加载中...')
            .fontSize(13)
            .fontColor('rgba(58,47,36,0.5)')
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.shelf_bg'))
  }

  @Builder
  ChapterList() {
    List({ space: 0 }) {
      if (this.content !== null) {
        ForEach(this.content.chapters, (ch: Chapter, idx: number) => {
          ListItem() {
            Row() {
              Text(ch.title)
                .fontSize(15)
                .fontColor(idx === (this.book as Book).chapterIndex ? $r('app.color.primary') : $r('app.color.theme_paper_text'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (idx === (this.book as Book).chapterIndex) {
                Text('读到这')
                  .fontSize(11)
                  .fontColor($r('app.color.primary'))
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
            .onClick(() => this.readAt(idx, 0))
          }
        }, (ch: Chapter, idx: number) => `${idx}`)
      }
    }
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: 'rgba(0,0,0,0.06)', startMargin: 16, endMargin: 16 })
  }

  @Builder
  BookmarkList() {
    if (this.bookmarks.length === 0) {
      Column({ space: 8 }) {
        Text('暂无书签')
          .fontSize(14)
          .fontColor('rgba(58,47,36,0.5)')
        Text('在阅读时长按文本可添加书签')
          .fontSize(12)
          .fontColor('rgba(58,47,36,0.4)')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        ForEach(this.bookmarks, (m: Bookmark, idx: number) => {
          ListItem() {
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text(`第 ${m.chapterIndex + 1} 章`)
                  .fontSize(13)
                  .fontColor($r('app.color.primary'))
                Text(m.excerpt)
                  .fontSize(13)
                  .fontColor($r('app.color.theme_paper_text'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('✕')
                .fontSize(16)
                .fontColor('rgba(58,47,36,0.5)')
                .onClick(async () => {
                  this.bookmarks = await BookRepository.removeBookmark((this.book as Book).id, m);
                })
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
            .onClick(() => this.readAt(m.chapterIndex, m.charOffset))
          }
        }, (m: Bookmark) => `${m.chapterIndex}_${m.charOffset}_${m.createdAt}`)
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: 'rgba(0,0,0,0.06)', startMargin: 16, endMargin: 16 })
    }
  }

  private formatSize(size: number): string {
    if (size < 1024) return `${size} B`;
    if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
    return `${(size / 1024 / 1024).toFixed(1)} MB`;
  }
}
