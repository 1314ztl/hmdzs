import { common } from '@kit.AbilityKit';
import { Book } from '../models/Book';
import { BookRepository } from '../data/BookRepository';
import { BookDataSource } from '../data/BookDataSource';
import { BookCover } from '../components/BookCover';
import { NavRouter } from '../common/NavRouter';
import { Constants } from '../common/Constants';

/**
 * 书架页面(主页内容)
 * 支持:搜索、排序、最近阅读横幅、进度徽章,LazyForEach 按需渲染优化长列表
 */
@Component
export struct BookShelfPage {
  @State books: Book[] = [];
  @State recentBook: Book | null = null;
  @State keyword: string = '';
  @State sortBy: number = Constants.SORT_RECENT;
  @State searching: boolean = false;
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
    this.applyFilter();
    this.recentBook = await BookRepository.getRecentBook();
  }

  private applyFilter(): void {
    let list = this.books.slice();
    const kw = this.keyword.trim().toLowerCase();
    if (kw.length > 0) {
      list = list.filter(b =>
        b.title.toLowerCase().includes(kw) || (b.author && b.author.toLowerCase().includes(kw)));
    }
    list = BookRepository.sortBooks(list, this.sortBy);
    this.dataSource.setData(list);
  }

  private displayCount(): number {
    return this.dataSource.totalCount();
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

  private cycleSort(): void {
    this.sortBy = (this.sortBy + 1) % 3;
    this.applyFilter();
  }

  private sortLabel(): string {
    if (this.sortBy === Constants.SORT_ADDED) {
      return '最近加入';
    }
    if (this.sortBy === Constants.SORT_TITLE) {
      return '按书名';
    }
    return '最近阅读';
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 8 }) {
        Text('鸿蒙书阁')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.theme_paper_text'))
          .layoutWeight(1)
        this.IconButton('🔍', () => { this.searching = !this.searching; if (!this.searching) { this.keyword = ''; this.applyFilter(); } })
        this.IconButton('＋', () => {
          AppStorage.setOrCreate<boolean>('scanAutoPick', true);
          NavRouter.push('scan');
        })
        this.IconButton('⚙', () => NavRouter.push('settings'))
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 12 })
      .backgroundColor($r('app.color.shelf_bg'))

      // 搜索栏
      if (this.searching) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '搜索书名 / 作者', text: this.keyword })
            .layoutWeight(1)
            .height(38)
            .backgroundColor('#FFFFFF')
            .borderRadius(19)
            .padding({ left: 16, right: 16 })
            .onChange((v: string) => { this.keyword = v; this.applyFilter(); })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
        .transition(TransitionEffect.move(TransitionEdge.TOP).animation({ duration: 180 }))
      }

      // 排序 + 数量条
      if (this.books.length > 0) {
        Row({ space: 6 }) {
          Text(`${this.displayCount()} 本书`)
            .fontSize(12)
            .fontColor('rgba(58,47,36,0.55)')
            .layoutWeight(1)
          Text(`⇅ ${this.sortLabel()}`)
            .fontSize(12)
            .fontColor($r('app.color.primary'))
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('rgba(139,94,60,0.1)')
            .borderRadius(12)
            .onClick(() => this.cycleSort())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 8 })
      }

      // 最近阅读横幅
      if (this.recentBook !== null && this.keyword.trim().length === 0) {
        RecentBanner({ book: this.recentBook as Book, onOpen: () => {
          AppStorage.setOrCreate<string>('readerBookId', (this.recentBook as Book).id);
          NavRouter.push('reader');
        }})
      }

      // 书架列表
      if (this.books.length === 0) {
        this.EmptyView()
      } else if (this.displayCount() === 0) {
        this.NoResultView()
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
          .columnsGap(14)
          .rowsGap(18)
          .padding(16)
          .width('100%')
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
  IconButton(icon: string, action: () => void) {
    Text(icon)
      .fontSize(20)
      .fontColor($r('app.color.theme_paper_text'))
      .width(40)
      .height(40)
      .textAlign(TextAlign.Center)
      .borderRadius(20)
      .onClick(() => action())
  }

  @Builder
  EmptyView() {
    Column({ space: 14 }) {
      Text('📖')
        .fontSize(44)
        .width(92).height(92)
        .textAlign(TextAlign.Center)
        .backgroundColor('rgba(139,94,60,0.08)')
        .borderRadius(46)
      Text('书架空空如也')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.theme_paper_text'))
      Text('导入本地 TXT / EPUB,开启你的阅读之旅')
        .fontSize(12)
        .fontColor('rgba(58,47,36,0.55)')
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

  @Builder
  NoResultView() {
    Column({ space: 8 }) {
      Text('🔍')
        .fontSize(36)
      Text(`未找到与"${this.keyword}"相关的书籍`)
        .fontSize(14)
        .fontColor('rgba(58,47,36,0.55)')
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
        .width(42)
        .height(58)
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
        Row({ space: 6 }) {
          Text(`第 ${Math.min(this.book.chapterIndex + 1, this.book.chapterCount)} 章`)
            .fontSize(11)
            .fontColor('rgba(58,47,36,0.6)')
          Text(`· ${BookRepository.progressPercent(this.book)}%`)
            .fontSize(11)
            .fontColor($r('app.color.primary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('继续 ›')
        .fontSize(13)
        .fontColor('#FFFFFF')
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .backgroundColor($r('app.color.primary'))
        .borderRadius(16)
    }
    .width('100%')
    .padding(12)
    .margin({ left: 16, right: 16, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
    .onClick(() => this.onOpen())
  }
}
