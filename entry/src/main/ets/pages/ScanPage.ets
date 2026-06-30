import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { Book } from '../models/Book';
import { BookRepository } from '../data/BookRepository';
import { FileScanner, ScannedFile } from '../utils/FileScanner';
import { NavRouter } from '../common/NavRouter';

/**
 * 扫描与分类管理页面
 * 功能:批量扫描本地 TXT/EPUB、按格式分类、加入书架
 */
@Component
export struct ScanPage {
  @State scanned: ScannedFile[] = [];
  @State shelfPaths: string[] = [];
  @Watch('onCategoryChange')
  @State category: string = 'all';
  @State importing: boolean = false;
  @State addingPath: string = '';
  @State displayed: ScannedFile[] = [];
  @State txtCount: number = 0;
  @State epubCount: number = 0;
  @State notOnShelfCount: number = 0;

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.Context;
    await BookRepository.init(ctx);
    await this.refresh();
    const autoPick = AppStorage.get<boolean>('scanAutoPick') ?? false;
    if (autoPick) {
      AppStorage.setOrCreate<boolean>('scanAutoPick', false);
      this.doImport();
    }
  }

  private onCategoryChange(): void {
    this.recompute();
  }

  private recompute(): void {
    this.txtCount = this.scanned.filter(f => f.format === 'txt').length;
    this.epubCount = this.scanned.filter(f => f.format === 'epub').length;
    this.notOnShelfCount = this.scanned.filter(f => !this.isOnShelf(f)).length;
    if (this.category === 'all') {
      this.displayed = this.scanned.slice();
    } else {
      this.displayed = this.scanned.filter(f => f.format === this.category);
    }
  }

  async refresh(): Promise<void> {
    const ctx = getContext(this) as common.Context;
    this.scanned = FileScanner.scanSandboxBooks(ctx);
    const shelf = await BookRepository.loadBookshelf();
    this.shelfPaths = shelf.map(b => b.path);
    this.recompute();
  }

  private async doImport(): Promise<void> {
    if (this.importing) {
      return;
    }
    this.importing = true;
    const ctx = getContext(this) as common.Context;
    const files = await FileScanner.importFromPicker(ctx);
    await this.refresh();
    this.importing = false;
    if (files.length > 0) {
      promptAction.showToast({ message: `已导入 ${files.length} 本书`, duration: 1500 });
    }
  }

  private isOnShelf(f: ScannedFile): boolean {
    return this.shelfPaths.includes(f.path);
  }

  private async addToShelf(f: ScannedFile): Promise<void> {
    this.addingPath = f.path;
    await BookRepository.addScannedFiles([f]);
    const shelf = await BookRepository.loadBookshelf();
    this.shelfPaths = shelf.map(b => b.path);
    this.recompute();
    this.addingPath = '';
    AppStorage.setOrCreate<boolean>('shelfDirty', true);
    promptAction.showToast({ message: '已加入书架', duration: 1200 });
  }

  private async addAll(): Promise<void> {
    const toAdd = this.scanned.filter(f => !this.isOnShelf(f));
    if (toAdd.length === 0) {
      promptAction.showToast({ message: '没有可加入的书籍', duration: 1200 });
      return;
    }
    this.importing = true;
    await BookRepository.addScannedFiles(toAdd);
    const shelf = await BookRepository.loadBookshelf();
    this.shelfPaths = shelf.map(b => b.path);
    this.recompute();
    this.importing = false;
    AppStorage.setOrCreate<boolean>('shelfDirty', true);
    promptAction.showToast({ message: `已加入 ${toAdd.length} 本书`, duration: 1500 });
  }

  private formatSize(size: number): string {
    if (size < 1024) return `${size} B`;
    if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
    return `${(size / 1024 / 1024).toFixed(1)} MB`;
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 12 }) {
        Text('‹')
          .fontSize(30)
          .fontColor($r('app.color.theme_paper_text'))
          .onClick(() => NavRouter.pop())
        Text('扫描管理')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.theme_paper_text'))
          .layoutWeight(1)
        Text(`${this.scanned.length} 本`)
          .fontSize(12)
          .fontColor('rgba(58,47,36,0.6)')
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 16 })
      .backgroundColor($r('app.color.shelf_bg'))

      // 操作区
      Column({ space: 10 }) {
        Button(this.importing ? '导入中...' : '扫描本地书籍')
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.primary'))
          .fontColor('#FFFFFF')
          .width('100%')
          .enabled(!this.importing)
          .onClick(() => this.doImport())
        if (this.notOnShelfCount > 0) {
          Button(`全部加入书架(${this.notOnShelfCount})`)
            .type(ButtonType.Capsule)
            .backgroundColor('rgba(139,94,60,0.12)')
            .fontColor($r('app.color.primary'))
            .width('100%')
            .onClick(() => this.addAll())
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 分类标签
      Row({ space: 8 }) {
        this.CatTab('all', `全部 ${this.scanned.length}`)
        this.CatTab('txt', `TXT ${this.txtCount}`)
        this.CatTab('epub', `EPUB ${this.epubCount}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      // 列表
      if (this.displayed.length === 0) {
        Column({ space: 8 }) {
          Text('暂无扫描结果')
            .fontSize(14)
            .fontColor('rgba(58,47,36,0.5)')
          Text('点击"扫描本地书籍"选择 TXT / EPUB 文件导入')
            .fontSize(12)
            .fontColor('rgba(58,47,36,0.4)')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.displayed, (f: ScannedFile) => {
            ListItem() {
              Row({ space: 12 }) {
                Column() {
                  Text(f.format.toUpperCase())
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                }
                .width(44).height(56)
                .backgroundColor(f.format === 'epub' ? '#6E5E8B' : '#5E6E8B')
                .borderRadius(6)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)

                Column({ space: 4 }) {
                  Text(f.title)
                    .fontSize(15)
                    .fontColor($r('app.color.theme_paper_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(`${this.formatSize(f.size)}  ·  ${f.format.toUpperCase()}`)
                    .fontSize(11)
                    .fontColor('rgba(58,47,36,0.5)')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (this.isOnShelf(f)) {
                  Text('已在书架')
                    .fontSize(12)
                    .fontColor('rgba(58,47,36,0.5)')
                } else if (this.addingPath === f.path) {
                  LoadingProgress().width(20).height(20)
                } else {
                  Button('加入')
                    .type(ButtonType.Capsule)
                    .backgroundColor('rgba(139,94,60,0.12)')
                    .fontColor($r('app.color.primary'))
                    .height(30)
                    .onClick(() => this.addToShelf(f))
                }
              }
              .width('100%')
              .padding(14)
              .backgroundColor('#FFFFFF')
            }
          }, (f: ScannedFile) => f.path)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: 'rgba(0,0,0,0.06)', startMargin: 14, endMargin: 14 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.shelf_bg'))
  }

  @Builder
  CatTab(key: string, label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.category === key ? '#FFFFFF' : 'rgba(58,47,36,0.7)')
      .backgroundColor(this.category === key ? $r('app.color.primary') : 'rgba(128,128,128,0.12)')
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .onClick(() => this.category = key)
  }
}
