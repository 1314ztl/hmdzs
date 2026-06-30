import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { Book, Bookmark, ReadSettings } from '../models/Book';
import { BookRepository } from '../data/BookRepository';
import { BookContent, Chapter } from '../models/Chapter';
import { Constants, ThemeFactory, ReadTheme, ThemeStyle } from '../common/Constants';
import { WindowUtil } from '../utils/WindowUtil';
import { SpeechUtil } from '../utils/SpeechUtil';
import { BackgroundTaskUtil } from '../utils/BackgroundTaskUtil';
import { NavRouter } from '../common/NavRouter';

/** 段落(含起始字符偏移) */
interface Paragraph {
  text: string;
  offset: number;
}

/**
 * 阅读器页面
 * 支持:滚动/左右翻页、阅读主题、字号/行距/段距、亮度、屏幕常亮、
 * 书签、进度记忆、朗读(Speech Kit)及睡眠定时
 */
@Component
export struct ReaderPage {
  @State book: Book | null = null;
  @State content: BookContent | null = null;
  @State settings: ReadSettings = {
    theme: ReadTheme.PAPER, fontSize: 18, lineHeight: 1.6, paragraphSpacing: 1.2,
    pageMode: Constants.PAGE_MODE_SCROLL, brightness: -1, keepScreenOn: true,
    speechRate: 50, speechPitch: 1.0
  } as ReadSettings;
  @State theme: ThemeStyle = ThemeFactory.get(ReadTheme.PAPER);
  @State chapterIndex: number = 0;
  @State toolbarVisible: boolean = false;
  @State panel: number = 0; // 0 无 1 阅读设置 2 朗读 3 目录
  @State isSpeaking: boolean = false;
  @State sleepMinutes: number = 0;
  @State sleepRemaining: number = 0;
  private scroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();
  private sleepTimerId: number = -1;
  private bgTaskRunning: boolean = false;

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.Context;
    await BookRepository.init(ctx);
    this.settings = await BookRepository.loadSettings();
    this.theme = ThemeFactory.get(this.settings.theme);
    const id = AppStorage.get<string>('readerBookId') ?? '';
    const shelf = await BookRepository.loadBookshelf();
    const found = shelf.find(b => b.id === id);
    if (found) {
      this.book = await BookRepository.loadProgress(found);
      this.content = await BookRepository.parseContent(this.book as Book);
      this.chapterIndex = (this.book as Book).chapterIndex;
    }
    await this.applyScreenSettings();
  }

  aboutToDisappear(): void {
    this.saveCurrentProgress();
    SpeechUtil.stop();
    this.clearSleepTimer();
    if (this.bgTaskRunning) {
      BackgroundTaskUtil.stopBackgroundRunning();
      this.bgTaskRunning = false;
    }
    const ctx = getContext(this) as common.Context;
    WindowUtil.resetBrightness(ctx);
    // 通知书架刷新(最近阅读/进度)
    AppStorage.setOrCreate<boolean>('shelfDirty', true);
  }

  private async applyScreenSettings(): Promise<void> {
    const ctx = getContext(this) as common.Context;
    await WindowUtil.setBrightness(ctx, this.settings.brightness);
    await WindowUtil.setKeepScreenOn(ctx, this.settings.keepScreenOn);
  }

  private currentChapter(): Chapter {
    if (this.content === null || this.content.chapters.length === 0) {
      return { title: '', content: '' };
    }
    const idx = Math.min(this.chapterIndex, this.content.chapters.length - 1);
    return this.content.chapters[idx];
  }

  /** 将章节切分为段落,返回段落及起始字符偏移 */
  private paragraphs(): Paragraph[] {
    const ch = this.currentChapter();
    const lines = ch.content.split('\n');
    const result: Paragraph[] = [];
    let offset = 0;
    for (const line of lines) {
      const t = line.trim();
      if (t.length > 0) {
        const p: Paragraph = { text: t, offset };
        result.push(p);
      }
      offset += line.length + 1;
    }
    if (result.length === 0) {
      const p: Paragraph = { text: '（本章无内容）', offset: 0 };
      result.push(p);
    }
    return result;
  }

  private saveCurrentProgress(): void {
    if (this.book === null) {
      return;
    }
    (this.book as Book).chapterIndex = this.chapterIndex;
    (this.book as Book).charOffset = 0;
    BookRepository.saveProgress(this.book as Book);
  }

  private gotoChapter(idx: number): void {
    if (this.content === null) {
      return;
    }
    const target = Math.max(0, Math.min(idx, this.content.chapters.length - 1));
    this.chapterIndex = target;
    (this.book as Book).chapterIndex = target;
    (this.book as Book).charOffset = 0;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.saveCurrentProgress();
    this.panel = 0;
  }

  private prevChapter(): void {
    if (this.chapterIndex > 0) {
      this.gotoChapter(this.chapterIndex - 1);
    }
  }

  private nextChapter(): void {
    if (this.content !== null && this.chapterIndex < this.content.chapters.length - 1) {
      this.gotoChapter(this.chapterIndex + 1);
    }
  }

  private addBookmarkAt(offset: number, text: string): void {
    if (this.book === null) {
      return;
    }
    const excerpt = text.length > 30 ? text.substring(0, 30) + '…' : text;
    const mark: Bookmark = {
      bookId: (this.book as Book).id,
      chapterIndex: this.chapterIndex,
      charOffset: offset,
      excerpt,
      createdAt: Date.now()
    };
    BookRepository.addBookmark(mark);
    promptAction.showToast({ message: '已添加书签', duration: 1500 });
  }

  // ---------- 朗读 ----------
  private async toggleSpeech(): Promise<void> {
    if (this.isSpeaking) {
      await SpeechUtil.stop();
      this.isSpeaking = false;
      this.clearSleepTimer();
      if (this.bgTaskRunning) {
        BackgroundTaskUtil.stopBackgroundRunning();
        this.bgTaskRunning = false;
      }
      return;
    }
    await this.startSpeech();
  }

  private async startSpeech(): Promise<void> {
    const ch = this.currentChapter();
    if (!ch.content) {
      return;
    }
    // 启动后台连续任务,支持后台朗读
    const ctx = getContext(this) as common.Context;
    const ok = await BackgroundTaskUtil.startBackgroundRunning(ctx, '朗读中');
    this.bgTaskRunning = ok;
    this.isSpeaking = true;
    SpeechUtil.setListener({
      onFinish: async () => {
        this.isSpeaking = false;
        // 自动下一章继续
        if (this.content !== null && this.chapterIndex < this.content.chapters.length - 1) {
          this.nextChapter();
          await new Promise<void>(r => setTimeout(() => r(), 200));
          await this.startSpeech();
        } else {
          this.clearSleepTimer();
          if (this.bgTaskRunning) {
            BackgroundTaskUtil.stopBackgroundRunning();
            this.bgTaskRunning = false;
          }
        }
      },
      onError: () => {
        this.isSpeaking = false;
        if (this.bgTaskRunning) {
          BackgroundTaskUtil.stopBackgroundRunning();
          this.bgTaskRunning = false;
        }
      }
    });
    await SpeechUtil.speak(ch.content, this.settings.speechRate, this.settings.speechPitch);
  }

  // ---------- 睡眠定时 ----------
  private startSleepTimer(): void {
    this.clearSleepTimer();
    if (this.sleepMinutes <= 0) {
      return;
    }
    this.sleepRemaining = this.sleepMinutes * 60;
    this.sleepTimerId = setInterval(() => {
      this.sleepRemaining--;
      if (this.sleepRemaining <= 0) {
        this.clearSleepTimer();
        SpeechUtil.stop();
        this.isSpeaking = false;
        if (this.bgTaskRunning) {
          BackgroundTaskUtil.stopBackgroundRunning();
          this.bgTaskRunning = false;
        }
        promptAction.showToast({ message: '睡眠定时结束,朗读已停止', duration: 2000 });
      }
    }, 1000);
  }

  private clearSleepTimer(): void {
    if (this.sleepTimerId !== -1) {
      clearInterval(this.sleepTimerId);
      this.sleepTimerId = -1;
    }
    this.sleepRemaining = 0;
  }

  private formatRemaining(): string {
    const m = Math.floor(this.sleepRemaining / 60);
    const s = this.sleepRemaining % 60;
    return `${m}:${s < 10 ? '0' + s : s}`;
  }

  build() {
    Stack() {
      // 阅读内容
      Column() {
        if (this.content !== null && this.book !== null) {
          if (this.settings.pageMode === Constants.PAGE_MODE_SCROLL) {
            this.ScrollReader()
          } else {
            this.SwipeReader()
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.bgHex)
      .gesture(TapGesture().onAction(() => {
        this.toolbarVisible = !this.toolbarVisible;
      }))

      // 顶部工具栏
      if (this.toolbarVisible) {
        this.TopBar()
      }
      // 底部工具栏
      if (this.toolbarVisible) {
        this.BottomBar()
      }
      // 阅读设置面板
      if (this.panel === 1) {
        this.SettingsSheet()
      }
      // 朗读面板
      if (this.panel === 2) {
        this.SpeechSheet()
      }
      // 目录面板
      if (this.panel === 3) {
        this.ChapterSheet()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ScrollReader() {
    Scroll(this.scroller) {
      Column() {
        Text(this.currentChapter().title)
          .fontSize(this.settings.fontSize + 4)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textHex)
          .width('100%')
          .margin({ bottom: 16 })
        ForEach(this.paragraphs(), (p: Paragraph) => {
          Text(p.text)
            .fontSize(this.settings.fontSize)
            .lineHeight(this.settings.fontSize * this.settings.lineHeight)
            .fontColor(this.theme.textHex)
            .width('100%')
            .margin({ bottom: this.settings.fontSize * (this.settings.paragraphSpacing - 1) + 8 })
            .textIndent(this.settings.fontSize * 2)
            .gesture(LongPressGesture().onAction(() => this.addBookmarkAt(p.offset, p.text)))
        }, (p: Paragraph) => `${p.offset}`)
        // 章节导航
        Row({ space: 12 }) {
          Button('上一章')
            .type(ButtonType.Capsule)
            .backgroundColor('rgba(128,128,128,0.15)')
            .fontColor(this.theme.textHex)
            .layoutWeight(1)
            .enabled(this.chapterIndex > 0)
            .onClick(() => this.prevChapter())
          Button('下一章')
            .type(ButtonType.Capsule)
            .backgroundColor('rgba(128,128,128,0.15)')
            .fontColor(this.theme.textHex)
            .layoutWeight(1)
            .enabled(this.content !== null && this.chapterIndex < (this.content as BookContent).chapters.length - 1)
            .onClick(() => this.nextChapter())
        }
        .width('100%')
        .margin({ top: 24, bottom: 40 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 24, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  SwipeReader() {
    Swiper(this.swiperController) {
      if (this.content !== null) {
        ForEach(this.content.chapters, (ch: Chapter, idx: number) => {
          Scroll() {
            Column() {
              Text(ch.title)
                .fontSize(this.settings.fontSize + 4)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.textHex)
                .width('100%')
                .margin({ bottom: 16 })
              ForEach(this.splitPara(ch.content), (p: Paragraph) => {
                Text(p.text)
                  .fontSize(this.settings.fontSize)
                  .lineHeight(this.settings.fontSize * this.settings.lineHeight)
                  .fontColor(this.theme.textHex)
                  .width('100%')
                  .margin({ bottom: this.settings.fontSize * (this.settings.paragraphSpacing - 1) + 8 })
                  .textIndent(this.settings.fontSize * 2)
                  .gesture(LongPressGesture().onAction(() => {
                    if (idx === this.chapterIndex) {
                      this.addBookmarkAt(p.offset, p.text);
                    }
                  }))
              }, (p: Paragraph) => `${idx}_${p.offset}`)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 24, bottom: 24 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }, (ch: Chapter, idx: number) => `${idx}`)
      }
    }
    .index(this.chapterIndex)
    .indicator(false)
    .loop(false)
    .width('100%')
    .layoutWeight(1)
    .onChange((index: number) => {
      this.chapterIndex = index;
      this.saveCurrentProgress();
    })
  }

  private splitPara(content: string): Paragraph[] {
    const lines = content.split('\n');
    const result: Paragraph[] = [];
    let offset = 0;
    for (const line of lines) {
      const t = line.trim();
      if (t.length > 0) {
        const p: Paragraph = { text: t, offset };
        result.push(p);
      }
      offset += line.length + 1;
    }
    if (result.length === 0) {
      const p: Paragraph = { text: '（本章无内容）', offset: 0 };
      result.push(p);
    }
    return result;
  }

  @Builder
  TopBar() {
    Row({ space: 12 }) {
      Text('‹')
        .fontSize(30)
        .fontColor(this.theme.textHex)
        .onClick(() => NavRouter.pop())
      Text(this.currentChapter().title)
        .fontSize(16)
        .fontColor(this.theme.textHex)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('✚')
        .fontSize(20)
        .fontColor(this.theme.textHex)
        .onClick(() => {
          const ch = this.currentChapter();
          this.addBookmarkAt(0, ch.title || ch.content.substring(0, 30));
        })
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.theme.bgHex)
    .position({ x: 0, y: 0 })
  }

  @Builder
  BottomBar() {
    Column() {
      Row({ space: 24 }) {
        this.BarItem('☰', '目录', () => { this.panel = 3; })
        this.BarItem('Aa', '设置', () => { this.panel = 1; })
        this.BarItem(this.isSpeaking ? '⏸' : '▶', this.isSpeaking ? '停止' : '朗读', () => this.toggleSpeech())
        this.BarItem('⏱', '定时', () => { this.panel = 2; })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
      .padding({ top: 8, bottom: 8 })
      // 章节进度条
      Row({ space: 8 }) {
        Text(`${this.chapterIndex + 1}/${this.content === null ? 1 : this.content.chapters.length}`)
          .fontSize(11)
          .fontColor(this.theme.textHex)
        Slider({
          value: this.chapterIndex,
          min: 0,
          max: this.content === null ? 1 : Math.max(1, this.content.chapters.length - 1),
          step: 1
        })
          .layoutWeight(1)
          .trackColor('rgba(128,128,128,0.2)')
          .selectedColor($r('app.color.primary'))
          .onChange((v: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.gotoChapter(Math.round(v));
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
    }
    .width('100%')
    .backgroundColor(this.theme.bgHex)
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
  }

  @Builder
  BarItem(icon: string, label: string, action: () => void) {
    Column({ space: 4 }) {
      Text(icon)
        .fontSize(20)
        .fontColor(this.theme.textHex)
      Text(label)
        .fontSize(11)
        .fontColor(this.theme.textHex)
    }
    .onClick(() => action())
  }

  @Builder
  SettingsSheet() {
    Column({ space: 16 }) {
      Text('阅读设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textHex)
        .width('100%')

      // 主题
      Row({ space: 12 }) {
        Text('主题')
          .fontSize(14)
          .fontColor(this.theme.textHex)
          .width(48)
        ForEach(ThemeFactory.THEMES, (t: ThemeStyle) => {
          Stack() {
            Column()
              .width(36).height(36)
              .backgroundColor(t.bgHex)
              .borderRadius(18)
              .border({ width: this.settings.theme === t.id ? 3 : 1, color: this.settings.theme === t.id ? $r('app.color.primary') : 'rgba(128,128,128,0.3)' })
          }
          .onClick(() => { this.settings.theme = t.id; this.theme = t; this.saveSettings(); })
        }, (t: ThemeStyle) => `${t.id}`)
      }.width('100%')

      // 字号
      this.SliderRow('字号', this.settings.fontSize, 14, 28, 1, (v: number) => {
        this.settings.fontSize = v; this.saveSettings();
      }, (v: number) => `${v}`)
      // 行距
      this.SliderRow('行距', this.settings.lineHeight, 1.2, 2.4, 0.1, (v: number) => {
        this.settings.lineHeight = v; this.saveSettings();
      }, (v: number) => v.toFixed(1))
      // 段距
      this.SliderRow('段距', this.settings.paragraphSpacing, 1.0, 2.5, 0.1, (v: number) => {
        this.settings.paragraphSpacing = v; this.saveSettings();
      }, (v: number) => v.toFixed(1))

      // 翻页模式
      Row({ space: 12 }) {
        Text('翻页')
          .fontSize(14)
          .fontColor(this.theme.textHex)
          .width(48)
        Button('上下滚动')
          .type(this.settings.pageMode === Constants.PAGE_MODE_SCROLL ? ButtonType.Capsule : ButtonType.Normal)
          .backgroundColor(this.settings.pageMode === Constants.PAGE_MODE_SCROLL ? $r('app.color.primary') : 'rgba(128,128,128,0.15)')
          .fontColor(this.settings.pageMode === Constants.PAGE_MODE_SCROLL ? '#FFFFFF' : this.theme.textHex)
          .onClick(() => { this.settings.pageMode = Constants.PAGE_MODE_SCROLL; this.saveSettings(); })
        Button('左右翻页')
          .type(this.settings.pageMode === Constants.PAGE_MODE_HORIZONTAL ? ButtonType.Capsule : ButtonType.Normal)
          .backgroundColor(this.settings.pageMode === Constants.PAGE_MODE_HORIZONTAL ? $r('app.color.primary') : 'rgba(128,128,128,0.15)')
          .fontColor(this.settings.pageMode === Constants.PAGE_MODE_HORIZONTAL ? '#FFFFFF' : this.theme.textHex)
          .onClick(() => { this.settings.pageMode = Constants.PAGE_MODE_HORIZONTAL; this.saveSettings(); })
      }.width('100%')

      // 亮度
      Row({ space: 12 }) {
        Text('亮度')
          .fontSize(14)
          .fontColor(this.theme.textHex)
          .width(48)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.brightness < 0 })
          .selectedColor($r('app.color.primary'))
          .onChange((on: boolean) => {
            this.settings.brightness = on ? -1 : 128;
            this.applyScreenSettings();
            this.saveSettings();
          })
        Slider({
          value: this.settings.brightness < 0 ? 80 : this.settings.brightness / 255 * 100,
          min: 10, max: 100, step: 1
        })
          .layoutWeight(1)
          .trackColor('rgba(128,128,128,0.2)')
          .selectedColor($r('app.color.primary'))
          .enabled(this.settings.brightness >= 0)
          .onChange((v: number) => {
            this.settings.brightness = Math.round(v / 100 * 255);
            this.applyScreenSettings();
            this.saveSettings();
          })
      }.width('100%')

      // 屏幕常亮
      Row({ space: 12 }) {
        Text('常亮')
          .fontSize(14)
          .fontColor(this.theme.textHex)
          .width(48)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.keepScreenOn })
          .selectedColor($r('app.color.primary'))
          .onChange((on: boolean) => {
            this.settings.keepScreenOn = on;
            this.applyScreenSettings();
            this.saveSettings();
          })
      }.width('100%')

      Button('关闭')
        .type(ButtonType.Capsule)
        .backgroundColor('rgba(128,128,128,0.15)')
        .fontColor(this.theme.textHex)
        .width('100%')
        .onClick(() => this.panel = 0)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.theme.bgHex)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
  }

  @Builder
  SliderRow(label: string, value: number, min: number, max: number, step: number,
            onChange: (v: number) => void, format: (v: number) => string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(14)
        .fontColor(this.theme.textHex)
        .width(48)
      Slider({ value, min, max, step })
        .layoutWeight(1)
        .trackColor('rgba(128,128,128,0.2)')
        .selectedColor($r('app.color.primary'))
        .onChange((v: number) => onChange(v))
      Text(format(value))
        .fontSize(12)
        .fontColor(this.theme.textHex)
        .width(36)
        .textAlign(TextAlign.Center)
    }.width('100%')
  }

  @Builder
  SpeechSheet() {
    Column({ space: 16 }) {
      Row() {
        Text('朗读')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textHex)
          .layoutWeight(1)
        if (this.sleepRemaining > 0) {
          Text(`剩余 ${this.formatRemaining()}`)
            .fontSize(13)
            .fontColor($r('app.color.primary'))
        }
      }.width('100%')

      Button(this.isSpeaking ? '停止朗读' : '开始朗读')
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.primary'))
        .fontColor('#FFFFFF')
        .width('100%')
        .onClick(() => this.toggleSpeech())

      this.SliderRow('语速', this.settings.speechRate, 1, 100, 1, (v: number) => {
        this.settings.speechRate = v; this.saveSettings();
      }, (v: number) => `${v}`)

      this.SliderRow('音调', this.settings.speechPitch, 0.5, 2.0, 0.1, (v: number) => {
        this.settings.speechPitch = v; this.saveSettings();
      }, (v: number) => v.toFixed(1))

      Text('睡眠定时')
        .fontSize(14)
        .fontColor(this.theme.textHex)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(Constants.SLEEP_TIMER_OPTIONS, (m: number) => {
          Text(m === 0 ? '关闭' : `${m} 分钟`)
            .fontSize(13)
            .fontColor(this.sleepMinutes === m ? '#FFFFFF' : this.theme.textHex)
            .backgroundColor(this.sleepMinutes === m ? $r('app.color.primary') : 'rgba(128,128,128,0.15)')
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(16)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.sleepMinutes = m;
              if (m === 0) {
                this.clearSleepTimer();
              } else {
                this.startSleepTimer();
              }
            })
        }, (m: number) => `${m}`)
      }.width('100%')

      Button('关闭')
        .type(ButtonType.Capsule)
        .backgroundColor('rgba(128,128,128,0.15)')
        .fontColor(this.theme.textHex)
        .width('100%')
        .onClick(() => this.panel = 0)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.theme.bgHex)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
  }

  @Builder
  ChapterSheet() {
    Column() {
      Text('目录')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textHex)
        .width('100%')
        .padding(16)
      List() {
        if (this.content !== null) {
          ForEach(this.content.chapters, (ch: Chapter, idx: number) => {
            ListItem() {
              Text(ch.title)
                .fontSize(15)
                .fontColor(idx === this.chapterIndex ? $r('app.color.primary') : this.theme.textHex)
                .width('100%')
                .padding(14)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => this.gotoChapter(idx))
            }
          }, (ch: Chapter, idx: number) => `${idx}`)
        }
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: 'rgba(128,128,128,0.15)', startMargin: 14, endMargin: 14 })
    }
    .width('100%')
    .height('60%')
    .backgroundColor(this.theme.bgHex)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
  }

  private saveSettings(): void {
    BookRepository.saveSettings(this.settings);
  }
}
