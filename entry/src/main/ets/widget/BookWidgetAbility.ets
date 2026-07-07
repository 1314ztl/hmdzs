import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/Constants';
import { Book } from '../models/Book';

const TAG = 'BookWidgetAbility';

/** 构造空数据 Record */
function emptyData(): Record<string, Object> {
  const data: Record<string, Object> = {
    'title': '暂无阅读书籍',
    'author': '点击选择书籍开始阅读',
    'progress': 0,
    'chapterInfo': '',
    'hasBook': false,
    'coverColor': '#8B5E3C',
    'bookId': ''
  };
  return data;
}

/**
 * 服务卡片 FormExtensionAbility
 * 在卡片添加/更新时读取最近阅读书籍,推送至卡片展示
 */
export default class BookWidgetAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(0x0000, TAG, 'onAddForm');
    // 首次添加返回空数据,系统随后会触发 onUpdateForm 拉取最新数据
    return formBindingData.createFormBindingData(emptyData());
  }

  async onUpdateForm(formId: string): Promise<void> {
    hilog.info(0x0000, TAG, 'onUpdateForm: %{public}s', formId);
    try {
      const data = await this.buildData();
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (e) {
      hilog.error(0x0000, TAG, 'updateForm failed: %{public}s', JSON.stringify(e));
    }
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(0x0000, TAG, 'onCastToNormalForm: %{public}s', formId);
  }

  onEvent(formId: string, message: string): void {
    hilog.info(0x0000, TAG, 'onEvent: %{public}s %{public}s', formId, message);
  }

  onRemoveForm(formId: string): void {
    hilog.info(0x0000, TAG, 'onRemoveForm: %{public}s', formId);
  }

  /**
   * 读取最近阅读书籍并构造卡片数据
   */
  private async buildData(): Promise<Record<string, Object>> {
    try {
      const prefs = await preferences.getPreferences(this.context, Constants.PREFS_NAME);
      const recentId = (await prefs.get(Constants.KEY_RECENT_BOOK, '')).toString();
      if (!recentId) {
        return emptyData();
      }
      const shelfRaw = (await prefs.get(Constants.KEY_BOOKSHELF, '[]')).toString();
      const shelf: Book[] = JSON.parse(shelfRaw) as Book[];
      const book = shelf.find(b => b.id === recentId);
      if (!book) {
        return emptyData();
      }
      const total = Math.max(1, book.chapterCount);
      const progress = book.lastReadAt > 0
        ? Math.min(100, Math.max(0, (book.chapterIndex + 1) / total * 100))
        : 0;
      const data: Record<string, Object> = {
        'title': book.title,
        'author': book.author || '佚名',
        'progress': Math.round(progress),
        'chapterInfo': `第 ${Math.min(book.chapterIndex + 1, book.chapterCount)} / ${book.chapterCount} 章`,
        'hasBook': true,
        'coverColor': book.coverColor,
        'bookId': book.id
      };
      return data;
    } catch (e) {
      hilog.error(0x0000, TAG, 'buildData failed: %{public}s', JSON.stringify(e));
      return emptyData();
    }
  }
}
