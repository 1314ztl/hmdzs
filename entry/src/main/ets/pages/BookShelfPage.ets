import { common } from '@kit.AbilityKit';
import { Book } from '../models/Book';
import { BookRepository } from '../data/BookRepository';
import { BookDataSource } from '../data/BookDataSource';
import { BookCover } from '../components/BookCover';
import { NavRouter } from '../common/NavRouter';

/**
 * 书架页面(Navigation 主页内容)
 * 使用 LazyForEach 按需渲染书籍,优化长列表性能
 */
@Component
export struct BookShelfPage {
  @State books: Book[] = [];
  @State recentBook: Book | null = null;
  @StorageLink('shelfDirty') @Watch('onDirty') shelfDirty: boolean = false;
  private dataSource: BookDataSource = new BookDataSource([]);

  aboutToAppear(): void {
    this.refresh();
  }

  onDirty(): void {
    if (this.shelfDirty) {
      this.shelfDirty = false;
      this.refresh();
    }
  }

  async refresh(): Promise<void> {
    const ctx = getContext(this) as common.Context;
    await BookRepository.init(ctx);
    this.books = await BookRepository.loadBookshelf();
    this.dataSource.setData(this.books);
    this.recentBook = await BookRepository.getRecentBook();
  }

  private openDetail(book: Book): void {
    AppStorage.setOrCreate<string>('detailBookId', book.id);
    NavRouter.push('detail');
  }

  private confirmDelete(book: Book): void {
    AlertDialog.show({
      title: '移除书籍',
      message: `确定从书架移除《${book.title}》?将同时删除本地文件。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '移除',
        fontColor: '#D43C3C',
        action: async () => {
          await BookRepository.removeBook(book);
          await this.refresh();
        }
      }
    });
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 12 }) {
        Text('鸿蒙书阁')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.theme_paper_text'))
          .layoutWeight(1)
        Text('＋')
          .fontSize(26)
          .fontColor($r('app.color.theme_paper_text'))
          .onClick(() => {
            AppStorage.setOrCreate<boolean>('scanAutoPick', true);
            NavRouter.push('scan');
          })
        Text('⚙')
          .fontSize(22)
          .fontColor($r('app.color.theme_paper_text'))
          .onClick(() => NavRouter.push('settings'))
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.shelf_bg'))

      // 最近阅读横幅
      if (this.recentBook !== null) {
        RecentBanner({ book: this.recentBook as Book, onOpen: () => {
          AppStorage.setOrCreate<string>('readerBookId', (this.recentBook as Book).id);
          NavRouter.push('reader');
        }})
      }

      // 书架列表
      if (this.books.length === 0) {
        this.EmptyView()
      } else {
        Scroll() {
          Grid() {
            LazyForEach(this.dataSource, (book: Book) => {
              GridItem() {
                Column({ space: 6 }) {
                  BookCover({ book: book })
                    .width('100%')
                    .aspectRatio(0.72)
                  Text(book.title)
                    .fontSize(13)
                    .fontColor($r('app.color.theme_paper_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
                .width('100%')
                .onClick(() => this.openDetail(book))
                .gesture(LongPressGesture().onAction(() => this.confirmDelete(book)))
              }
            }, (book: Book) => book.id)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(12)
          .rowsGap(16)
          .padding(16)
          .width('100%')
          .height(this.books.length === 0 ? 0 : '100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.shelf_bg'))
  }

  @Builder
  EmptyView() {
    Column({ space: 12 }) {
      Text('书')
        .fontSize(40)
        .fontColor('rgba(139,94,60,0.5)')
        .width(80).height(80)
        .textAlign(TextAlign.Center)
        .backgroundColor('rgba(139,94,60,0.08)')
        .borderRadius(40)
      Text('书架空空如也')
        .fontSize(15)
        .fontColor($r('app.color.theme_paper_text'))
      Text('点击右上角 + 扫描本地 TXT / EPUB 导入')
        .fontSize(12)
        .fontColor('rgba(58,47,36,0.6)')
      Button('导入书籍')
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.primary'))
        .fontColor('#FFFFFF')
        .margin({ top: 8 })
        .onClick(() => {
          AppStorage.setOrCreate<boolean>('scanAutoPick', true);
          NavRouter.push('scan');
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}

/**
 * 最近阅读横幅
 */
@Component
struct RecentBanner {
  @Prop book: Book;
  onOpen: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      BookCover({ book: this.book, compact: true })
        .width(40)
        .height(56)
      Column({ space: 4 }) {
        Text('继续阅读')
          .fontSize(11)
          .fontColor('rgba(58,47,36,0.6)')
        Text(this.book.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.theme_paper_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`第 ${Math.min(this.book.chapterIndex + 1, this.book.chapterCount)} 章`)
          .fontSize(11)
          .fontColor('rgba(58,47,36,0.6)')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('继续 ›')
        .fontSize(13)
        .fontColor($r('app.color.primary'))
    }
    .width('100%')
    .padding(12)
    .margin({ left: 12, right: 12, top: 8 })
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: 2 })
    .onClick(() => this.onOpen())
  }
}
