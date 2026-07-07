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
 * 书签、进度记忆(含章节内滚动偏移)、朗读(Speech Kit)及睡眠定时
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
  @State loading: boolean = true;
  @State chapterProgress: number = 0; // 章节内滚动百分比 0-100
  private scroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();
  private sleepTimerId: number = -1;
  private bgTaskRunning: boolean = false;
  private pendingCharOffset: number = 0; // 待恢复的章节内偏移
  private restored: boolean = false;

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
      try {
        this.content = await BookRepository.parseContent(this.book as Book);
      } catch (e) {
        this.content = { chapters: [{ title: '错误', content: '无法打开该书籍' }], totalChars: 0 };
      }
      this.chapterIndex = Math.min((this.book as Book).chapterIndex, (this.content as BookContent).chapters.length - 1);
      this.pendingCharOffset = (this.book as Book).charOffset;
    }
    this.loading = false;
    await this.applyScreenSettings();
    // 恢复章节内滚动位置
    this.restoreScrollPosition();
  }

  aboutToDisappear(): void {
    this.saveCurrentProgress(true);
    SpeechUtil.stop();
    SpeechUtil.setListener(null);
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

  private chapterCount(): number {
    return this.content === null ? 0 : this.content.chapters.length;
  }

  /** 将章节切分为段落,返回段落及起始字符偏移 */
  private paragraphs(): Paragraph[] {
    return this.splitPara(this.currentChapter().content);
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

  /** 根据当前滚动位置估算章节内字符偏移 */
  private estimateCharOffset(): number {
    const ch = this.currentChapter();
    if (ch.content.length === 0) {
      return 0;
    }
    const ratio = this.chapterProgress / 100;
    return Math.round(ch.content.length * ratio);
  }

  /** 恢复到之前保存的章节内滚动位置 */
  private restoreScrollPosition(): void {
    if (this.restored || this.pendingCharOffset <= 0 || this.content === null) {
      this.restored = true;
      return;
    }
    const ch = this.currentChapter();
    if (ch.content.length === 0) {
      this.restored = true;
      return;
    }
    const ratio = Math.min(1, this.pendingCharOffset / ch.content.length);
    // 延迟到布局完成后再按比例估算像素滚动
    setTimeout(() => {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: this.estimatePixelFromRatio(ratio), animation: false });
      } catch (e) {
        // ignore
      }
      this.restored = true;
    }, 150);
  }

  /** 由比例估算滚动像素(基于内容高度粗略估算) */
  private estimatePixelFromRatio(ratio: number): number {
    // 每字符约占用高度 ≈ 字号 * 行距 / 每行字数(约 18 字)
    const ch = this.currentChapter();
    const perLine = 18;
    const lineH = this.settings.fontSize * this.settings.lineHeight;
    const totalLines = ch.content.length / perLine;
    const estHeight = totalLines * lineH;
    return Math.max(0, estHeight * ratio);
  }

  private saveCurrentProgress(immediate: boolean): void {
    if (this.book === null) {
      return;
    }
    (this.book as Book).chapterIndex = this.chapterIndex;
    (this.book as Book).charOffset = this.estimateCharOffset();
    BookRepository.saveProgress(this.book as Book, immediate);
  }

  private gotoChapter(idx: number): void {
    if (this.content === null) {
      return;
    }
    const target = Math.max(0, Math.min(idx, this.content.chapters.length - 1));
    this.chapterIndex = target;
    (this.book as Book).chapterIndex = target;
    (this.book as Book).charOffset = 0;
    this.chapterProgress = 0;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    this.saveCurrentProgress(true);
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
      promptAction.showToast({ message: '本章无可朗读内容', duration: 1500 });
      return;
    }
    const ctx = getContext(this) as common.Context;
    const ok = await BackgroundTaskUtil.startBackgroundRunning(ctx, '朗读中');
    this.bgTaskRunning = ok;
    this.isSpeaking = true;
    SpeechUtil.setListener({
      onFinish: async () => {
        // 自动下一章继续
        if (this.content !== null && this.chapterIndex < this.content.chapters.length - 1) {
          this.nextChapter();
          await new Promise<void>(r => setTimeout(() => r(), 200));
          await this.startSpeech();
        } else {
          this.isSpeaking = false;
          this.clearSleepTimer();
          if (this.bgTaskRunning) {
            BackgroundTaskUtil.stopBackgroundRunning();
            this.bgTaskRunning = false;
          }
          promptAction.showToast({ message: '已朗读完本书', duration: 1500 });
        }
      },
      onError: (err: string) => {
        this.isSpeaking = false;
        if (this.bgTaskRunning) {
          BackgroundTaskUtil.stopBackgroundRunning();
          this.bgTaskRunning = false;
        }
        promptAction.showToast({ message: '朗读失败,请检查网络或语音服务', duration: 2000 });
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
    this.sleepMinutes = 0;
  }

  private formatRemaining(): string {
    const m = Math.floor(this.sleepRemaining / 60);
    const s = this.sleepRemaining % 60;
    return `${m}:${s < 10 ? '0' + s : s}`;
  }

  /** 半透明遮罩色(用于面板背景蒙层) */
  private overlayColor(): string {
    return this.settings.theme === ReadTheme.DARK ? 'rgba(0,0,0,0.5)' : 'rgba(0,0,0,0.35)';
  }

  build() {
    Stack() {
      // 阅读内容
      Column() {
        if (this.loading) {
          this.LoadingView()
        } else if (this.content !== null && this.book !== null) {
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
      .onClick(() => {
        if (this.panel !== 0) {
          this.panel = 0;
        } else {
          this.toolbarVisible = !this.toolbarVisible;
        }
      })

      // 顶部工具栏
      if (this.toolbarVisible) {
        this.TopBar()
      }
      // 底部工具栏
      if (this.toolbarVisible) {
        this.BottomBar()
      }

      // 面板蒙层
      if (this.panel !== 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.overlayColor())
          .onClick(() => this.panel = 0)
          .transition(TransitionEffect.opacity.animation({ duration: 200 }))
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
  LoadingView() {
    Column({ space: 12 }) {
      LoadingProgress().width(44).height(44).color(this.theme.textHex)
      Text('正在打开书籍…')
        .fontSize(13)
        .fontColor(this.theme.textHex)
        .opacity(0.7)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ScrollReader() {
    Scroll(this.scroller) {
      Column() {
        Text(this.currentChapter().title)
          .fontSize(this.settings.fontSize + 5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textHex)
          .width('100%')
          .margin({ bottom: 20 })
        ForEach(this.paragraphs(), (p: Paragraph) => {
          Text(p.text)
            .fontSize(this.settings.fontSize)
            .lineHeight(this.settings.fontSize * this.settings.lineHeight)
            .fontColor(this.theme.textHex)
            .width('100%')
            .margin({ bottom: this.settings.fontSize * (this.settings.paragraphSpacing - 1) + 8 })
            .textIndent(this.settings.fontSize * 2)
            .gesture(LongPressGesture().onAction(() => this.addBookmarkAt(p.offset, p.text)))
        }, (p: Paragraph) => `${this.chapterIndex}_${p.offset}`)
        // 章节导航
        Row({ space: 12 }) {
          Button('上一章')
            .type(ButtonType.Capsule)
            .backgroundColor('rgba(128,128,128,0.15)')
            .fontColor(this.theme.textHex)
            .layoutWeight(1)
            .enabled(this.chapterIndex > 0)
            .opacity(this.chapterIndex > 0 ? 1 : 0.4)
            .onClick(() => this.prevChapter())
          Button('下一章')
            .type(ButtonType.Capsule)
            .backgroundColor('rgba(128,128,128,0.15)')
            .fontColor(this.theme.textHex)
            .layoutWeight(1)
            .enabled(this.content !== null && this.chapterIndex < (this.content as BookContent).chapters.length - 1)
            .opacity(this.content !== null && this.chapterIndex < (this.content as BookContent).chapters.length - 1 ? 1 : 0.4)
            .onClick(() => this.nextChapter())
        }
        .width('100%')
        .margin({ top: 28, bottom: 48 })
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 28, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .onDidScroll(() => {
      // 更新章节内进度百分比,并防抖保存
      const y = this.scroller.currentOffset().yOffset;
      const est = this.estimatePixelFromRatio(1);
      this.chapterProgress = est > 0 ? Math.min(100, Math.max(0, Math.round(y / est * 100))) : 0;
      if (this.restored) {
        this.saveCurrentProgress(false);
      }
    })
  }

  @Builder
  SwipeReader() {
    Swiper(this.swiperController) {
      if (this.content !== null) {
        ForEach(this.content.chapters, (ch: Chapter, idx: number) => {
          Scroll() {
            Column() {
              Text(ch.title)
                .fontSize(this.settings.fontSize + 5)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.textHex)
                .width('100%')
                .margin({ bottom: 20 })
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
            .padding({ left: 22, right: 22, top: 28, bottom: 24 })
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
    .cachedCount(1)
    .width('100%')
    .layoutWeight(1)
    .onChange((index: number) => {
      this.chapterIndex = index;
      this.chapterProgress = 0;
      this.saveCurrentProgress(true);
    })
  }

  @Builder
  TopBar() {
    Row({ space: 12 }) {
      Text('‹')
        .fontSize(30)
        .fontColor(this.theme.textHex)
        .width(36)
        .textAlign(TextAlign.Center)
        .onClick(() => NavRouter.pop())
      Text(this.currentChapter().title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textHex)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('✚')
        .fontSize(20)
        .fontColor(this.theme.textHex)
        .width(36)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          const ch = this.currentChapter();
          this.addBookmarkAt(this.estimateCharOffset(), ch.title || ch.content.substring(0, 30));
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 8, top: 4 })
    .backgroundColor(this.theme.bgHex)
    .shadow({ radius: 6, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.move(TransitionEdge.TOP).animation({ duration: 220 }))
  }

  @Builder
  BottomBar() {
    Column() {
      // 章节进度条
      Row({ space: 10 }) {
        Text('上一章')
          .fontSize(12)
          .fontColor(this.theme.textHex)
          .opacity(this.chapterIndex > 0 ? 0.8 : 0.3)
          .onClick(() => this.prevChapter())
        Slider({
          value: this.chapterIndex,
          min: 0,
          max: this.content === null ? 1 : Math.max(1, this.content.chapters.length - 1),
          step: 1
        })
          .layoutWeight(1)
          .trackColor('rgba(128,128,128,0.2)')
          .selectedColor($r('app.color.primary'))
          .blockColor($r('app.color.primary'))
          .onChange((v: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.gotoChapter(Math.round(v));
            }
          })
        Text('下一章')
          .fontSize(12)
          .fontColor(this.theme.textHex)
          .opacity(this.content !== null && this.chapterIndex < this.chapterCount() - 1 ? 0.8 : 0.3)
          .onClick(() => this.nextChapter())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 4 })
      Text(`第 ${this.chapterIndex + 1} / ${this.chapterCount()} 章`)
        .fontSize(11)
        .fontColor(this.theme.textHex)
        .opacity(0.6)
        .margin({ bottom: 4 })
      Divider().color('rgba(128,128,128,0.15)').strokeWidth(0.5)
      Row() {
        this.BarItem('☰', '目录', () => { this.panel = 3; })
        this.BarItem('Aa', '设置', () => { this.panel = 1; })
        this.BarItem(this.isSpeaking ? '⏸' : '🔊', this.isSpeaking ? '暂停' : '朗读', () => this.toggleSpeech())
        this.BarItem('⏱', '定时', () => { this.panel = 2; })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
      .padding({ top: 8, bottom: 10 })
    }
    .width('100%')
    .backgroundColor(this.theme.bgHex)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: -2 })
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
    .transition(TransitionEffect.move(TransitionEdge.BOTTOM).animation({ duration: 220 }))
  }

  @Builder
  BarItem(icon: string, label: string, action: () => void) {
    Column({ space: 4 }) {
      Text(icon)
        .fontSize(20)
        .fontColor(label === '朗读' && this.isSpeaking ? $r('app.color.primary') : this.theme.textHex)
      Text(label)
        .fontSize(11)
        .fontColor(this.theme.textHex)
        .opacity(0.85)
    }
    .layoutWeight(1)
    .padding({ top: 4, bottom: 4 })
    .onClick(() => action())
  }

  @Builder
  SheetHeader(title: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textHex)
        .layoutWeight(1)
      Text('✕')
        .fontSize(18)
        .fontColor(this.theme.textHex)
        .opacity(0.6)
        .onClick(() => this.panel = 0)
    }.width('100%')
  }

  @Builder
  SettingsSheet() {
    Column({ space: 18 }) {
      this.SheetHeader('阅读设置')

      // 主题
      Row({ space: 12 }) {
        Text('主题')
          .fontSize(14)
          .fontColor(this.theme.textHex)
          .width(48)
        ForEach(ThemeFactory.THEMES, (t: ThemeStyle) => {
          Stack() {
            Column()
              .width(38).height(38)
              .backgroundColor(t.bgHex)
              .borderRadius(19)
              .border({ width: this.settings.theme === t.id ? 3 : 1, color: this.settings.theme === t.id ? $r('app.color.primary') : 'rgba(128,128,128,0.3)' })
          }
          .onClick(() => { this.settings.theme = t.id; this.theme = t; this.saveSettings(); })
        }, (t: ThemeStyle) => `${t.id}`)
      }.width('100%')

      // 字号
      this.SliderRow('字号', this.settings.fontSize, 14, 30, 1, (v: number) => {
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
        this.ToggleButton('上下滚动', this.settings.pageMode === Constants.PAGE_MODE_SCROLL, () => {
          this.settings.pageMode = Constants.PAGE_MODE_SCROLL; this.saveSettings();
        })
        this.ToggleButton('左右翻页', this.settings.pageMode === Constants.PAGE_MODE_HORIZONTAL, () => {
          this.settings.pageMode = Constants.PAGE_MODE_HORIZONTAL; this.saveSettings();
        })
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
          value: this.settings.brightness < 0 ? 50 : this.settings.brightness / 255 * 100,
          min: 10, max: 100, step: 1
        })
          .layoutWeight(1)
          .trackColor('rgba(128,128,128,0.2)')
          .selectedColor($r('app.color.primary'))
          .enabled(this.settings.brightness >= 0)
          .opacity(this.settings.brightness >= 0 ? 1 : 0.4)
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
        Text('阅读时保持屏幕常亮')
          .fontSize(13)
          .fontColor(this.theme.textHex)
          .opacity(0.7)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.keepScreenOn })
          .selectedColor($r('app.color.primary'))
          .onChange((on: boolean) => {
            this.settings.keepScreenOn = on;
            this.applyScreenSettings();
            this.saveSettings();
          })
      }.width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 32 })
    .backgroundColor(this.theme.bgHex)
    .borderRadius({ topLeft: 20, topRight: 20 })
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
    .transition(TransitionEffect.move(TransitionEdge.BOTTOM).animation({ duration: 260 }))
  }

  @Builder
  ToggleButton(label: string, active: boolean, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(active ? '#FFFFFF' : this.theme.textHex)
      .backgroundColor(active ? $r('app.color.primary') : 'rgba(128,128,128,0.15)')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(18)
      .onClick(() => action())
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
        .width(38)
        .textAlign(TextAlign.Center)
    }.width('100%')
  }

  @Builder
  SpeechSheet() {
    Column({ space: 16 }) {
      Row() {
        Text('朗读 · 定时')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textHex)
          .layoutWeight(1)
        if (this.sleepRemaining > 0) {
          Text(`剩余 ${this.formatRemaining()}`)
            .fontSize(13)
            .fontColor($r('app.color.primary'))
            .margin({ right: 12 })
        }
        Text('✕')
          .fontSize(18)
          .fontColor(this.theme.textHex)
          .opacity(0.6)
          .onClick(() => this.panel = 0)
      }.width('100%')

      Button(this.isSpeaking ? '停止朗读' : '开始朗读')
        .type(ButtonType.Capsule)
        .backgroundColor(this.isSpeaking ? 'rgba(212,60,60,0.9)' : $r('app.color.primary'))
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
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
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
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 32 })
    .backgroundColor(this.theme.bgHex)
    .borderRadius({ topLeft: 20, topRight: 20 })
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
    .transition(TransitionEffect.move(TransitionEdge.BOTTOM).animation({ duration: 260 }))
  }

  @Builder
  ChapterSheet() {
    Column() {
      Row() {
        Text('目录')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textHex)
          .layoutWeight(1)
        Text(`共 ${this.chapterCount()} 章`)
          .fontSize(12)
          .fontColor(this.theme.textHex)
          .opacity(0.6)
          .margin({ right: 12 })
        Text('✕')
          .fontSize(18)
          .fontColor(this.theme.textHex)
          .opacity(0.6)
          .onClick(() => this.panel = 0)
      }
      .width('100%')
      .padding(16)
      List() {
        if (this.content !== null) {
          ForEach(this.content.chapters, (ch: Chapter, idx: number) => {
            ListItem() {
              Row({ space: 8 }) {
                Text(ch.title)
                  .fontSize(15)
                  .fontColor(idx === this.chapterIndex ? $r('app.color.primary') : this.theme.textHex)
                  .fontWeight(idx === this.chapterIndex ? FontWeight.Medium : FontWeight.Normal)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (idx === this.chapterIndex) {
                  Text('●')
                    .fontSize(10)
                    .fontColor($r('app.color.primary'))
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => this.gotoChapter(idx))
            }
          }, (ch: Chapter, idx: number) => `${idx}`)
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({ strokeWidth: 0.5, color: 'rgba(128,128,128,0.12)', startMargin: 16, endMargin: 16 })
    }
    .width('100%')
    .height('66%')
    .backgroundColor(this.theme.bgHex)
    .borderRadius({ topLeft: 20, topRight: 20 })
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
    .transition(TransitionEffect.move(TransitionEdge.BOTTOM).animation({ duration: 260 }))
  }

  private saveSettings(): void {
    BookRepository.saveSettings(this.settings);
  }
}
