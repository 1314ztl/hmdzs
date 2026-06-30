let storage = new LocalStorage();

/**
 * 服务卡片:展示最近阅读书籍及进度
 * 数据由 BookWidgetAbility 通过 formBindingData 推送
 */
@Entry(storage)
@Component
struct BookWidgetCard {
  @LocalStorageProp('title') title: string = '暂无阅读书籍';
  @LocalStorageProp('author') author: string = '点击选择书籍开始阅读';
  @LocalStorageProp('progress') progress: number = 0;
  @LocalStorageProp('chapterInfo') chapterInfo: string = '';
  @LocalStorageProp('hasBook') hasBook: boolean = false;
  @LocalStorageProp('coverColor') coverColor: string = '#8B5E3C';
  @LocalStorageProp('bookId') bookId: string = '';

  build() {
    Column() {
      Row({ space: 10 }) {
        // 封面色块
        Column() {
          Text(this.hasBook ? '书' : '+')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(44)
        .height(60)
        .backgroundColor(this.coverColor)
        .borderRadius(6)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text(this.hasBook ? '最近阅读' : '鸿蒙书阁')
            .fontSize(11)
            .fontColor('rgba(58,47,36,0.6)')
          Text(this.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#3A2F24')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.author)
            .fontSize(11)
            .fontColor('rgba(58,47,36,0.5)')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 6 })

      if (this.hasBook) {
        // 进度
        Row({ space: 6 }) {
          Text(this.chapterInfo)
            .fontSize(10)
            .fontColor('rgba(58,47,36,0.6)')
          Blank()
          Text(`${Math.round(this.progress)}%`)
            .fontSize(10)
            .fontColor('#8B5E3C')
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('90%')
          .color('#8B5E3C')
          .backgroundColor('rgba(139,94,60,0.15)')
          .margin({ bottom: 10 })
      } else {
        Text('打开应用添加本地小说')
          .fontSize(11)
          .fontColor('rgba(58,47,36,0.45)')
          .margin({ bottom: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAF6EC')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': { 'bookId': this.bookId }
      });
    })
  }
}
