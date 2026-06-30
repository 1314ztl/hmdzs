import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/Constants';

const TAG = 'FileScanner';

/** 扫描到的文件元数据 */
export interface ScannedFile {
  /** 文件名(不含扩展名),可作为书名 */
  title: string;
  /** 沙箱内相对路径(相对 filesDir) */
  path: string;
  /** 格式扩展名(小写,无点) */
  format: string;
  /** 文件大小(字节) */
  size: number;
}

/**
 * 本地书籍扫描与导入工具
 * 采用文件选择器(picker)导入,拷贝至应用沙箱 books 目录,
 * 再扫描沙箱目录实现批量扫描与分类管理,无需额外权限。
 */
export class FileScanner {
  /** 确保书籍目录存在,返回绝对路径 */
  static ensureBooksDir(context: common.Context): string {
    const dir = `${context.filesDir}/${Constants.BOOKS_DIR}`;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir);
    }
    return dir;
  }

  /**
   * 通过文件选择器批量导入书籍到沙箱
   * @returns 导入成功的文件元数据列表
   */
  static async importFromPicker(context: common.Context): Promise<ScannedFile[]> {
    const dir = FileScanner.ensureBooksDir(context);
    const docPicker = new picker.DocumentViewPicker();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 100;
    options.fileSuffixFilters = ['.txt', '.epub'];
    let uris: string[] = [];
    try {
      uris = (await docPicker.select(options)) as string[];
    } catch (e) {
      hilog.error(0x0000, TAG, 'picker select failed: %{public}s', JSON.stringify(e));
      return [];
    }
    if (!uris || uris.length === 0) {
      return [];
    }

    const result: ScannedFile[] = [];
    for (const uri of uris) {
      try {
        const meta = await FileScanner.copyToSandbox(context, uri, dir);
        if (meta) {
          result.push(meta);
        }
      } catch (e) {
        hilog.error(0x0000, TAG, 'copy failed for %{public}s: %{public}s', uri, JSON.stringify(e));
      }
    }
    return result;
  }

  /**
   * 将单个 URI 文件拷贝到沙箱
   */
  private static async copyToSandbox(context: common.Context, uri: string, dir: string): Promise<ScannedFile | null> {
    const fileName = FileScanner.extractFileName(uri);
    const dotIdx = fileName.lastIndexOf('.');
    const base = dotIdx > 0 ? fileName.substring(0, dotIdx) : fileName;
    const ext = dotIdx > 0 ? fileName.substring(dotIdx + 1).toLowerCase() : '';
    if (!Constants.SUPPORTED_EXT.includes(ext)) {
      return null;
    }
    // 去重文件名
    let destName = fileName;
    let destPath = `${dir}/${destName}`;
    let counter = 1;
    while (fs.accessSync(destPath)) {
      destName = `${base}(${counter}).${ext}`;
      destPath = `${dir}/${destName}`;
      counter++;
    }

    const srcFile: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const destFile: fs.File = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      await fs.copyFile(srcFile.fd, destFile.fd);
    } finally {
      fs.closeSync(srcFile);
      fs.closeSync(destFile);
    }
    const stat: fs.Stat = fs.statSync(destPath);
    return {
      title: base,
      path: `${Constants.BOOKS_DIR}/${destName}`,
      format: ext,
      size: stat.size
    };
  }

  /**
   * 从 URI 提取文件名
   */
  private static extractFileName(uri: string): string {
    const clean = uri.split('?')[0].split('#')[0];
    const seg = clean.split('/').filter(s => s.length > 0);
    const last = seg.length > 0 ? seg[seg.length - 1] : 'book';
    try {
      return decodeURIComponent(last);
    } catch (e) {
      return last;
    }
  }

  /**
   * 扫描沙箱 books 目录下所有支持的书籍文件
   */
  static scanSandboxBooks(context: common.Context): ScannedFile[] {
    const dir = FileScanner.ensureBooksDir(context);
    let names: string[] = [];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      hilog.error(0x0000, TAG, 'list dir failed: %{public}s', JSON.stringify(e));
      return [];
    }
    const result: ScannedFile[] = [];
    for (const name of names) {
      const dotIdx = name.lastIndexOf('.');
      const ext = dotIdx > 0 ? name.substring(dotIdx + 1).toLowerCase() : '';
      if (!Constants.SUPPORTED_EXT.includes(ext)) {
        continue;
      }
      const full = `${dir}/${name}`;
      try {
        const stat: fs.Stat = fs.statSync(full);
        if (stat.isDirectory()) {
          continue;
        }
        result.push({
          title: dotIdx > 0 ? name.substring(0, dotIdx) : name,
          path: `${Constants.BOOKS_DIR}/${name}`,
          format: ext,
          size: stat.size
        });
      } catch (e) {
        // ignore single file error
      }
    }
    return result;
  }

  /**
   * 删除沙箱中的书籍文件
   */
  static removeBookFile(context: common.Context, relativePath: string): void {
    const full = `${context.filesDir}/${relativePath}`;
    try {
      fs.unlinkSync(full);
    } catch (e) {
      hilog.error(0x0000, TAG, 'remove file failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 读取书籍文件为 ArrayBuffer
   */
  static readBuffer(context: common.Context, relativePath: string): ArrayBuffer {
    const full = `${context.filesDir}/${relativePath}`;
    const file: fs.File = fs.openSync(full, fs.OpenMode.READ_ONLY);
    try {
      const stat: fs.Stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      return buf;
    } finally {
      fs.closeSync(file);
    }
  }
}
