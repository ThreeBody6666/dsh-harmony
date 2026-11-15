/**
 * 自检：在没有真机日志的情况下，把「本机引擎」依赖的每一层单独验一遍。
 * 结果直接显示在界面上，用户截一张图就能定位断点。
 */
import vmhost from 'libentry.so';
import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';
import { common } from '@kit.AbilityKit';

export class SelfTestItem {
  name: string = '';
  ok: boolean = false;
  detail: string = '';

  constructor(name: string, ok: boolean, detail: string) {
    this.name = name;
    this.ok = ok;
    this.detail = detail;
  }
}

const ZIP_ASSET: string = 'selftest.zip';
const CORE_ASSET: string = 'core.zip';
const HOOK_ASSET: string = 'hook.mjs';

export class SelfTest {
  private ctx: common.UIAbilityContext;
  private out: SelfTestItem[] = [];

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private add(name: string, ok: boolean, detail: string): void {
    this.out.push(new SelfTestItem(name, ok, detail));
  }

  /** 逐项跑，返回结果列表（不抛异常，失败也记成一项）。 */
  async run(): Promise<SelfTestItem[]> {
    this.out = [];
    await this.checkNative();
    await this.checkRawfileFd();
    await this.checkRawfileContent();
    await this.checkFileIo();
    await this.checkUnzip();
    await this.checkHostStart();
    return this.out;
  }

  private async checkNative(): Promise<void> {
    try {
      const version: string = vmhost.nativeVersion();
      const kind: string = vmhost.hostKind();
      this.add('原生库 libentry.so', true, version + ' / 后端=' + kind);
      this.add('Node 后端', kind === 'libnode', kind === 'libnode' ? '已编入 libnode' : '是桩实现（没编进 libnode）');
    } catch (e) {
      this.add('原生库 libentry.so', false, (e as Error).message);
    }
  }

  private async checkRawfileFd(): Promise<void> {
    try {
      const raw = await this.ctx.resourceManager.getRawFd(CORE_ASSET);
      const size: number = raw.length;
      await this.ctx.resourceManager.closeRawFd(CORE_ASSET);
      this.add('core.zip 可读（fd）', size > 0, size > 0 ? Math.floor(size / 1048576) + ' MB' : '大小 0');
    } catch (e) {
      this.add('core.zip 可读（fd）', false, (e as Error).message);
    }
  }

  private async checkRawfileContent(): Promise<void> {
    try {
      const data: Uint8Array = await this.ctx.resourceManager.getRawFileContent(HOOK_ASSET);
      this.add('hook.mjs 可读（content）', data.length > 0, data.length + ' 字节');
    } catch (e) {
      this.add('hook.mjs 可读（content）', false, (e as Error).message);
    }
  }

  private async checkFileIo(): Promise<void> {
    const path: string = this.ctx.filesDir + '/selftest.txt';
    try {
      const f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, 'ok');
      fs.closeSync(f);
      const size: number = fs.statSync(path).size;
      this.add('应用目录读写', size === 2, '写入 ' + size + ' 字节 @ ' + this.ctx.filesDir);
    } catch (e) {
      this.add('应用目录读写', false, (e as Error).message);
    }
  }

  private async checkUnzip(): Promise<void> {
    const dir: string = this.ctx.filesDir + '/selftest-unzip';
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const zipPath: string = this.ctx.filesDir + '/selftest.zip';
      if (!fs.accessSync(zipPath)) {
        const data: Uint8Array = await this.ctx.resourceManager.getRawFileContent(ZIP_ASSET);
        const f = fs.openSync(zipPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        fs.writeSync(f.fd, data.buffer as ArrayBuffer);
        fs.closeSync(f);
      }
      await zlib.decompressFile(zipPath, dir);
      const ok: boolean = fs.accessSync(dir + '/hello.txt');
      this.add('zip 解压（zlib）', ok, ok ? '解出 hello.txt' : '解压完成但没找到文件');
    } catch (e) {
      this.add('zip 解压（zlib）', false, (e as Error).message);
    }
  }

  private async checkHostStart(): Promise<void> {
    try {
      const dummy: string = this.ctx.filesDir + '/no-such-core';
      const err: string = vmhost.hostStart('', dummy, this.ctx.filesDir, 3080);
      // 期望拿到「核心树目录为空」这类明确错误，说明原生调用链是通的
      const ok: boolean = err.length > 0;
      this.add('宿主调用链', ok, ok ? '返回：' + err : '返回空串（异常）');
    } catch (e) {
      this.add('宿主调用链', false, (e as Error).message);
    }
  }
}
