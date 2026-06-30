import { Book } from '../models/Book';

/**
 * LazyForEach 数据源:书架列表按需渲染,优化长列表性能
 */
export class BookDataSource implements IDataSource {
  private books: Book[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(books: Book[] = []) {
    this.books = books;
  }

  totalCount(): number {
    return this.books.length;
  }

  getData(index: number): Book {
    return this.books[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  /** 全量替换 */
  setData(books: Book[]): void {
    this.books = books;
    this.notifyReload();
  }

  /** 追加 */
  append(books: Book[]): void {
    const start = this.books.length;
    this.books = this.books.concat(books);
    this.listeners.forEach(l => l.onDatasetChange([{ type: DataOperationType.ADD, index: start, count: books.length }]));
  }

  /** 移除单个 */
  remove(book: Book): void {
    const idx = this.books.findIndex(b => b.id === book.id);
    if (idx >= 0) {
      this.books.splice(idx, 1);
      this.listeners.forEach(l => l.onDatasetChange([{ type: DataOperationType.DELETE, index: idx, count: 1 }]));
    }
  }

  /** 更新单个 */
  update(book: Book): void {
    const idx = this.books.findIndex(b => b.id === book.id);
    if (idx >= 0) {
      this.books[idx] = book;
      this.listeners.forEach(l => l.onDatasetChange([{ type: DataOperationType.CHANGE, index: idx }]));
    }
  }

  list(): Book[] {
    return this.books;
  }

  private notifyReload(): void {
    this.listeners.forEach(l => l.onDatasetChange([{ type: DataOperationType.RELOAD }]));
  }
}
