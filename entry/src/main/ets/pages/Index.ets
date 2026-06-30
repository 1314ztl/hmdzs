import { BookShelfPage } from './BookShelfPage';
import { ReaderPage } from './ReaderPage';
import { SettingsPage } from './SettingsPage';
import { ScanPage } from './ScanPage';
import { BookDetailPage } from './BookDetailPage';
import { RouteInfo } from '../common/NavRouter';

@Entry
@Component
struct Index {
  @StorageLink('navStack') stack: RouteInfo[] = [];
  @StorageLink('pendingOpenBookId') @Watch('onPendingChange') pendingOpenBookId: string = '';

  onPendingChange(): void {
    if (this.pendingOpenBookId && this.pendingOpenBookId.length > 0) {
      const id = this.pendingOpenBookId;
      this.pendingOpenBookId = '';
      AppStorage.setOrCreate<string>('readerBookId', id);
      this.stack = [];
      this.stack = [{ name: 'reader' }];
    }
  }

  @Builder
  PageContent() {
    if (this.stack.length > 0 && this.stack[this.stack.length - 1].name === 'reader') {
      ReaderPage();
    } else if (this.stack.length > 0 && this.stack[this.stack.length - 1].name === 'settings') {
      SettingsPage();
    } else if (this.stack.length > 0 && this.stack[this.stack.length - 1].name === 'scan') {
      ScanPage();
    } else if (this.stack.length > 0 && this.stack[this.stack.length - 1].name === 'detail') {
      BookDetailPage();
    } else {
      BookShelfPage();
    }
  }

  build() {
    Stack() {
      this.PageContent()
    }
    .width('100%')
    .height('100%')
  }
}
