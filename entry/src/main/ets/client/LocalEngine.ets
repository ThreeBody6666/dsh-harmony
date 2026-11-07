/**
 * 本机模式：HAP 自带 Node（libnode）+ dsh 核心树，进程内起 `127.0.0.1:3080`。
 *
 * 思路与 DSHM 同构（进程内 Node、不发子进程、不走虚拟机），界面仍是我们这套
 * dsh-go 风格。流程：
 *   1. 首启把 rawfile 里的 core.zip 解到私有目录（只需一次）
 *   2. 把 hook.mjs 写出来（让引擎的 stdout 落盘，宿主从中捞 token）
 *   3. 调原生宿主 hostStart()，在独立线程里跑 node
 *   4. 轮询 engine.log 里的 `?token=`，拿到就登录 127.0.0.1:3080
 */

import vmhost from 'libentry.so';
import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'LocalEngine';
const CORE_ZIP: string = 'core.zip';
const HOOK_ASSET: string = 'hook.mjs';
const ENGINE_PORT: number = 3080;
const TOKEN_WAIT_MS: number = 120000;

export class LocalEngineInfo {
  baseUrl: string = '';
  token: string = '';
}

export class LocalEngineError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
    this.name = 'LocalEngineError';
  }
}

export class LocalEngine {
  private context: common.UIAbilityContext;
  private baseDir: string = '';
  private coreDir: string = '';
  private hookPath: string = '';
  private logPath: string = '';
  private stepLog: string = '';
  private onProgress: (text: string) => void = (text: string) => {};

  constructor(context: common.UIAbilityContext, onProgress?: (text: string) => void) {
    this.context = context;
    this.baseDir = context.filesDir + '/local';
    this.coreDir = this.baseDir + '/core';
    this.hookPath = this.baseDir + '/hook.mjs';
    this.logPath = context.filesDir + '/dshhome/engine.log';
    this.stepLog = this.baseDir + '/step.log';
    if (onProgress !== undefined) {
      this.onProgress = onProgress;
    }
  }

  /** 写一条步骤日志（应用内可看，不用连 hdc）。 */
  private step(text: string): void {
    hilog.info(0x0000, TAG, '%{public}s', text);
    try {
      if (!fs.accessSync(this.baseDir)) {
        fs.mkdirSync(this.baseDir, true);
      }
      const line = new Date().toISOString() + '  ' + text + '\n';
      const f = fs.openSync(this.stepLog, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      fs.writeSync(f.fd, line);
      fs.closeSync(f);
    } catch (e) {
    }
  }

  /** 给 UI 用的日志尾部（步骤日志 + 引擎日志）。 */
  readDiagnostics(): string {
    let out: string = '';
    out += '[步骤]\n' + this.tailOf(this.stepLog, 2000) + '\n';
    out += '[引擎]\n' + this.tailOf(this.logPath, 2000);
    return out;
  }

  private tailOf(path: string, bytes: number): string {
    if (!fs.accessSync(path)) {
      return '(无)';
    }
    try {
      const size = fs.statSync(path).size;
      const take = size > bytes ? bytes : size;
      const buf = new ArrayBuffer(take);
      const f = fs.openSync(path, fs.OpenMode.READ_ONLY);
      fs.readSync(f.fd, buf, { offset: size - take });
      fs.closeSync(f);
      const arr = new Uint8Array(buf);
      let text = '';
      for (let i = 0; i < arr.length; i++) {
        text += String.fromCharCode(arr[i]);
      }
      return text;
    } catch (e) {
      return '(读取失败)';
    }
  }

  /** 调试用：宿主类型（libnode / stub）。 */
  hostKind(): string {
    try {
      return vmhost.hostKind();
    } catch (e) {
      return 'native 未加载';
    }
  }

  status(): string {
    try {
      return vmhost.hostStatus();
    } catch (e) {
      return 'unknown';
    }
  }

  /** 有没有把核心树打进来。 */
  async hasCore(): Promise<boolean> {
    try {
      const data: Uint8Array = await this.context.resourceManager.getRawFileContent(CORE_ZIP);
      return data !== undefined && data.length > 0;
    } catch (e) {
      return false;
    }
  }

  /**
   * 释放 rawfile。优先用 getRawFd 分块拷（158MB 不进内存），
   * 拿不到 fd 时退回整体读。
   */
  private async extractRaw(asset: string, dest: string): Promise<void> {
    try {
      const raw = await this.context.resourceManager.getRawFd(asset);
      const out = fs.openSync(dest, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        const CHUNK: number = 4 * 1024 * 1024;
        const buf = new ArrayBuffer(CHUNK);
        let done = 0;
        while (done < raw.length) {
          const want: number = raw.length - done > CHUNK ? CHUNK : raw.length - done;
          const got: number = fs.readSync(raw.fd, buf, { offset: raw.offset + done, length: want });
          if (got <= 0) {
            break;
          }
          fs.writeSync(out.fd, buf.slice(0, got));
          done += got;
          this.onProgress(`释放资源 ${Math.floor(done / 1048576)}MB / ${Math.floor(raw.length / 1048576)}MB`);
        }
      } finally {
        fs.closeSync(out);
        await this.context.resourceManager.closeRawFd(asset);
      }
      return;
    } catch (e) {
      this.step('getRawFd 不可用，退回整体读取：' + (e as Error).message);
    }
    const data: Uint8Array = await this.context.resourceManager.getRawFileContent(asset);
    const file = fs.openSync(dest, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, data.buffer as ArrayBuffer);
    } finally {
      fs.closeSync(file);
    }
  }

  /** 首启准备：解核心树 + 落钩子脚本。 */
  private async prepare(): Promise<void> {
    this.step('开始准备本机引擎');
    if (!fs.accessSync(this.baseDir)) {
      fs.mkdirSync(this.baseDir, true);
    }
    if (!fs.accessSync(this.hookPath)) {
      this.onProgress('释放 hook.mjs');
      await this.extractRaw(HOOK_ASSET, this.hookPath);
      this.step('hook.mjs 就位');
    }
    if (!fs.accessSync(this.coreDir + '/node_modules')) {
      const zipPath: string = this.baseDir + '/core.zip';
      if (!fs.accessSync(zipPath)) {
        this.onProgress('释放核心树（158MB，首次启动要等）');
        await this.extractRaw(CORE_ZIP, zipPath);
        this.step('core.zip 落地');
      }
      fs.mkdirSync(this.coreDir, true);
      this.onProgress('解压核心树…');
      this.step('开始解压 core.zip');
      await zlib.decompressFile(zipPath, this.coreDir);
      this.step('核心树解压完成');
    }
  }

  /** 启动本机引擎；返回 127.0.0.1 地址与 token。 */
  async start(): Promise<LocalEngineInfo> {
    if (!(await this.hasCore())) {
      throw new LocalEngineError(
        'core/missing',
        'HAP 里没有核心树（rawfile/core.zip）。跑 scripts/prepare-local-runtime.sh 后重新构建。'
      );
    }
    await this.prepare();

    const cwd: string = this.context.filesDir;
    this.onProgress('启动 Node 宿主…');
    this.step('调用 hostStart，coreDir=' + this.coreDir);
    let error: string = '';
    try {
      error = vmhost.hostStart(this.hookPath, this.coreDir, cwd, ENGINE_PORT);
    } catch (e) {
      const err = e as BusinessError;
      throw new LocalEngineError('native/crash', '原生宿主调用失败：' + err.message);
    }
    this.step('hostStart 返回：' + (error.length === 0 ? 'ok' : error));
    if (error.length > 0) {
      throw new LocalEngineError('host/start', error);
    }

    this.onProgress('等引擎启动…');
    const token: string = await this.waitForToken();
    this.step('拿到 token');
    const info = new LocalEngineInfo();
    info.baseUrl = `http://127.0.0.1:${ENGINE_PORT}`;
    info.token = token;
    return info;
  }

  /** 引擎启动后会打印 http://127.0.0.1:3080/?token=…，这里轮询日志捞它。 */
  private async waitForToken(): Promise<string> {
    const deadline: number = Date.now() + TOKEN_WAIT_MS;
    while (Date.now() < deadline) {
      const token: string = this.readToken();
      if (token.length > 0) {
        return token;
      }
      await sleep(500);
    }
    const tail: string = this.readLogTail();
    throw new LocalEngineError(
      'host/token-timeout',
      '两分钟没等到引擎 token。日志尾部：' + tail
    );
  }

  private readToken(): string {
    const text: string = this.readLogTail();
    const idx: number = text.lastIndexOf('token=');
    if (idx < 0) {
      return '';
    }
    let out: string = '';
    for (let i = idx + 6; i < text.length; i++) {
      const c: string = text.charAt(i);
      if (c === ' ' || c === '\n' || c === '\r' || c === '"') {
        break;
      }
      out += c;
    }
    return out;
  }

  private readLogTail(): string {
    if (!fs.accessSync(this.logPath)) {
      return '';
    }
    try {
      const size: number = fs.statSync(this.logPath).size;
      const take: number = size > 4000 ? 4000 : size;
      const buffer = new ArrayBuffer(take);
      const file = fs.openSync(this.logPath, fs.OpenMode.READ_ONLY);
      try {
        fs.readSync(file.fd, buffer, { offset: size - take });
      } finally {
        fs.closeSync(file);
      }
      const bytes = new Uint8Array(buffer);
      let out: string = '';
      for (let i = 0; i < bytes.length; i++) {
        out += String.fromCharCode(bytes[i]);
      }
      return out;
    } catch (e) {
      return '';
    }
  }

  stop(): void {
    try {
      vmhost.hostStop();
    } catch (e) {
      hilog.warn(0x0000, TAG, 'hostStop failed');
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}
