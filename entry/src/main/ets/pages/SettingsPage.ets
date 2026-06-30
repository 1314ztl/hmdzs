import { common } from '@kit.AbilityKit';
import { ReadSettings } from '../models/Book';
import { BookRepository } from '../data/BookRepository';
import { Constants, ThemeFactory, ReadTheme, ThemeStyle } from '../common/Constants';
import { NavRouter } from '../common/NavRouter';

/**
 * 设置页面:全局默认阅读主题、字号、行距、翻页模式、亮度、常亮、朗读
 */
@Component
export struct SettingsPage {
  @State settings: ReadSettings = {
    theme: ReadTheme.PAPER, fontSize: 18, lineHeight: 1.6, paragraphSpacing: 1.2,
    pageMode: Constants.PAGE_MODE_SCROLL, brightness: -1, keepScreenOn: true,
    speechRate: 50, speechPitch: 1.0
  } as ReadSettings;
  @State saved: boolean = false;

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.Context;
    await BookRepository.init(ctx);
    this.settings = await BookRepository.loadSettings();
  }

  private async save(): Promise<void> {
    await BookRepository.saveSettings(this.settings);
    this.saved = true;
    setTimeout(() => this.saved = false, 1500);
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 12 }) {
        Text('‹')
          .fontSize(30)
          .fontColor($r('app.color.theme_paper_text'))
          .onClick(() => NavRouter.pop())
        Text('阅读设置')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.theme_paper_text'))
          .layoutWeight(1)
        Text(this.saved ? '已保存' : '')
          .fontSize(12)
          .fontColor($r('app.color.primary'))
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 16 })
      .backgroundColor($r('app.color.shelf_bg'))

      Scroll() {
        Column({ space: 18 }) {
          // 预览
          Column({ space: 8 }) {
            Text('预览效果')
              .fontSize(13)
              .fontColor('rgba(58,47,36,0.6)')
            Column({ space: 6 }) {
              Text('第一章 初入江湖')
                .fontSize(this.settings.fontSize + 4)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeFactory.get(this.settings.theme).textHex)
              Text('少年提剑出门去,一蓑烟雨任平生。江湖路远,且听风吟。')
                .fontSize(this.settings.fontSize)
                .lineHeight(this.settings.fontSize * this.settings.lineHeight)
                .fontColor(ThemeFactory.get(this.settings.theme).textHex)
                .textIndent(this.settings.fontSize * 2)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(ThemeFactory.get(this.settings.theme).bgHex)
            .borderRadius(12)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          this.Section('阅读主题')
          Row({ space: 14 }) {
            ForEach(ThemeFactory.THEMES, (t: ThemeStyle) => {
              Column({ space: 4 }) {
                Stack() {
                  Column()
                    .width(44).height(44)
                    .backgroundColor(t.bgHex)
                    .borderRadius(22)
                    .border({ width: this.settings.theme === t.id ? 3 : 1, color: this.settings.theme === t.id ? $r('app.color.primary') : 'rgba(128,128,128,0.3)' })
                }
                Text(t.name)
                  .fontSize(11)
                  .fontColor(this.settings.theme === t.id ? $r('app.color.primary') : 'rgba(58,47,36,0.6)')
              }
              .onClick(() => { this.settings.theme = t.id; this.save(); })
            }, (t: ThemeStyle) => `${t.id}`)
          }.width('100%')

          this.Section('字号')
          this.SliderRow(this.settings.fontSize, 14, 28, 1, (v: number) => v.toString(), (v: number) => { this.settings.fontSize = v; this.save(); })

          this.Section('行距')
          this.SliderRow(this.settings.lineHeight, 1.2, 2.4, 0.1, (v: number) => v.toFixed(1), (v: number) => { this.settings.lineHeight = v; this.save(); })

          this.Section('段距')
          this.SliderRow(this.settings.paragraphSpacing, 1.0, 2.5, 0.1, (v: number) => v.toFixed(1), (v: number) => { this.settings.paragraphSpacing = v; this.save(); })

          this.Section('翻页模式')
          Row({ space: 12 }) {
            Button('上下滚动')
              .type(this.settings.pageMode === Constants.PAGE_MODE_SCROLL ? ButtonType.Capsule : ButtonType.Normal)
              .backgroundColor(this.settings.pageMode === Constants.PAGE_MODE_SCROLL ? $r('app.color.primary') : 'rgba(128,128,128,0.15)')
              .fontColor(this.settings.pageMode === Constants.PAGE_MODE_SCROLL ? '#FFFFFF' : $r('app.color.theme_paper_text'))
              .layoutWeight(1)
              .onClick(() => { this.settings.pageMode = Constants.PAGE_MODE_SCROLL; this.save(); })
            Button('左右翻页')
              .type(this.settings.pageMode === Constants.PAGE_MODE_HORIZONTAL ? ButtonType.Capsule : ButtonType.Normal)
              .backgroundColor(this.settings.pageMode === Constants.PAGE_MODE_HORIZONTAL ? $r('app.color.primary') : 'rgba(128,128,128,0.15)')
              .fontColor(this.settings.pageMode === Constants.PAGE_MODE_HORIZONTAL ? '#FFFFFF' : $r('app.color.theme_paper_text'))
              .layoutWeight(1)
              .onClick(() => { this.settings.pageMode = Constants.PAGE_MODE_HORIZONTAL; this.save(); })
          }.width('100%')

          this.Section('屏幕亮度')
          Row({ space: 12 }) {
            Text('跟随系统')
              .fontSize(14)
              .fontColor($r('app.color.theme_paper_text'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.brightness < 0 })
              .selectedColor($r('app.color.primary'))
              .onChange((on: boolean) => {
                this.settings.brightness = on ? -1 : 128;
                this.save();
              })
          }.width('100%')
          if (this.settings.brightness >= 0) {
            Slider({ value: this.settings.brightness / 255 * 100, min: 10, max: 100, step: 1 })
              .trackColor('rgba(128,128,128,0.2)')
              .selectedColor($r('app.color.primary'))
              .onChange((v: number) => { this.settings.brightness = Math.round(v / 100 * 255); this.save(); })
          }

          this.Section('屏幕常亮')
          Row({ space: 12 }) {
            Text('阅读时保持屏幕常亮')
              .fontSize(14)
              .fontColor($r('app.color.theme_paper_text'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.keepScreenOn })
              .selectedColor($r('app.color.primary'))
              .onChange((on: boolean) => { this.settings.keepScreenOn = on; this.save(); })
          }.width('100%')

          this.Section('朗读语速')
          this.SliderRow(this.settings.speechRate, 1, 100, 1, (v: number) => `${v}`, (v: number) => { this.settings.speechRate = v; this.save(); })

          this.Section('朗读音调')
          this.SliderRow(this.settings.speechPitch, 0.5, 2.0, 0.1, (v: number) => v.toFixed(1), (v: number) => { this.settings.speechPitch = v; this.save(); })

          Text('说明:以上为全局默认设置,阅读器内可临时调整。')
            .fontSize(11)
            .fontColor('rgba(58,47,36,0.45)')
            .width('100%')
            .margin({ top: 8, bottom: 24 })
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.shelf_bg'))
  }

  @Builder
  Section(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.theme_paper_text'))
      .width('100%')
  }

  @Builder
  SliderRow(value: number, min: number, max: number, step: number,
            format: (v: number) => string, onChange: (v: number) => void) {
    Row({ space: 12 }) {
      Slider({ value, min, max, step })
        .layoutWeight(1)
        .trackColor('rgba(128,128,128,0.2)')
        .selectedColor($r('app.color.primary'))
        .onChange((v: number) => onChange(v))
      Text(format(value))
        .fontSize(12)
        .fontColor($r('app.color.theme_paper_text'))
        .width(40)
        .textAlign(TextAlign.Center)
    }.width('100%')
  }
}
