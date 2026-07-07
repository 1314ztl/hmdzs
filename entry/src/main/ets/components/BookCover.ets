import { Book } from '../models/Book';
import { BookRepository } from '../data/BookRepository';

/**
 * 书籍封面组件:渐变色块 + 书名 + 作者 + 进度徽章
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

  /** 生成同色系深色作为渐变终点,营造书籍立体感 */
  private darken(hex: string): string {
    const h = hex.replace('#', '');
    if (h.length < 6) {
      return hex;
    }
    const r = Math.max(0, parseInt(h.substring(0, 2), 16) - 40);
    const g = Math.max(0, parseInt(h.substring(2, 4), 16) - 40);
    const b = Math.max(0, parseInt(h.substring(4, 6), 16) - 40);
    return `#${this.hex2(r)}${this.hex2(g)}${this.hex2(b)}`;
  }

  private hex2(n: number): string {
    const s = n.toString(16);
    return s.length < 2 ? `0${s}` : s;
  }

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
          Blank()
          if (this.book.lastReadAt > 0 && this.book.chapterCount > 0) {
            Text(`${BookRepository.progressPercent(this.book)}%`)
              .fontSize(this.compact ? 8 : 9)
              .fontColor('rgba(255,255,255,0.95)')
          }
        }.width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(this.compact ? 6 : 10)
      .alignItems(HorizontalAlign.Start)

      // 底部阅读进度条(仅在已读时显示)
      if (!this.compact && this.book.lastReadAt > 0 && this.book.chapterCount > 0) {
        Column()
          .width(`${BookRepository.progressPercent(this.book)}%`)
          .height(3)
          .backgroundColor('rgba(255,255,255,0.85)')
          .position({ x: 0, y: '100%' })
          .translate({ y: -3 })
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 145,
      colors: [[this.book.coverColor, 0.0], [this.darken(this.book.coverColor), 1.0]]
    })
    .borderRadius(this.compact ? 8 : 12)
    .shadow({ radius: this.compact ? 0 : 6, color: 'rgba(0,0,0,0.15)', offsetX: 0, offsetY: this.compact ? 0 : 2 })
    .clip(true)
  }
}
