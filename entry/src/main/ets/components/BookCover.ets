import { Book } from '../models/Book';

/**
 * 书籍封面组件:色块 + 书名 + 进度
 */
@Component
export struct BookCover {
  book: Book = {
    id: '', title: '', author: '', path: '', format: 'txt', size: 0,
    coverColor: '#8B5E3C', addedAt: 0, lastReadAt: 0, chapterCount: 0,
    chapterIndex: 0, charOffset: 0, totalChars: 0
  };
  /** 是否紧凑模式(最近阅读横幅) */
  compact: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 装饰书脊
      Column()
        .width('100%')
        .height(this.compact ? 6 : 8)
        .backgroundColor('rgba(255,255,255,0.25)')
        .position({ x: 0, y: 0 })

      Column({ space: 6 }) {
        Text(this.book.title)
          .fontSize(this.compact ? 12 : 16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.LEFT)
        if (this.book.author) {
          Text(this.book.author)
            .fontSize(this.compact ? 9 : 11)
            .fontColor('rgba(255,255,255,0.8)')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        Blank()
        Row({ space: 4 }) {
          Text(this.book.format.toUpperCase())
            .fontSize(this.compact ? 8 : 9)
            .fontColor('rgba(255,255,255,0.9)')
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .borderRadius(3)
            .backgroundColor('rgba(0,0,0,0.25)')
          if (this.book.chapterCount > 0) {
            Text(`${Math.min(this.book.chapterIndex + 1, this.book.chapterCount)}/${this.book.chapterCount}`)
              .fontSize(this.compact ? 8 : 9)
              .fontColor('rgba(255,255,255,0.9)')
          }
        }.width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(this.compact ? 6 : 10)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.book.coverColor)
    .borderRadius(this.compact ? 8 : 12)
    .clip(true)
  }
}
