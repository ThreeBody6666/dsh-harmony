/**
 * 本机模式：在手机内部起一台 Linux 虚拟机跑 DSH 引擎。
 *
 * 流程（对应 docs/LOCAL-ENGINE.md 的 P0/P1）：
 *   1. 校验 HAP 里是否带齐 kernel / rootfs（缺失就明确报错，不装死）
 *   2. 首次把 rawfile 释放到 filesDir/vm/（大文件，只在版本变化时重做）
 *   3. 调原生桥启动 VM，内部把客户机 3080 端口转发到本机 127.0.0.1
 *   4. 轮询共享目录里的 token 文件（VM 里 dsh web 启动后写入）
 *   5. 拿到 token 就等于拿到 baseUrl + token，交给现有登录流程
 *
 * 原生后端当前是「桩」——工程能跑，但会明确告诉你还没接入 qemu。
 */

import vmhost from 'libentry.so';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'LocalEngine';
const KERNEL_ASSET: string = 'vm/kernel_aarch64';
const ROOTFS_ASSET: string = 'vm/rootfs_aarch64.qcow2';
const ENGINE_PORT: number = 3080;
const TOKEN_WAIT_MS: number = 90000;

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
  private vmDir: string = '';
  private tokenPath: string = '';

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.vmDir = context.filesDir + '/vm';
    this.tokenPath = this.vmDir + '/share/dsh-token';
  }

  /** 原生桥是否可用（含后端类型），用于设置页展示。 */
  nativeInfo(): string {
    try {
      return vmhost.nativeVersion();
    } catch (e) {
      return 'native 未加载';
    }
  }

  status(): string {
    try {
      return vmhost.vmStatus();
    } catch (e) {
      return 'unknown';
    }
  }

  /** 资源是否齐备；缺哪个直接说哪个。 */
  async checkAssets(): Promise<string> {
    const missing: string[] = [];
    const assets: string[] = [KERNEL_ASSET, ROOTFS_ASSET];
    for (let i = 0; i < assets.length; i++) {
      try {
        const data: Uint8Array = await this.context.resourceManager.getRawFileContent(assets[i]);
        if (data === undefined || data.length === 0) {
          missing.push(assets[i]);
        }
      } catch (e) {
        missing.push(assets[i]);
      }
    }
    if (missing.length > 0) {
      return `HAP 里缺资源：${missing.join('、')}。跑 scripts/fetch-vm-assets.sh 拉取后重新构建。`;
    }
    return '';
  }

  /** 释放 rawfile 到应用私有目录；已存在则跳过。 */
  private async ensureFile(asset: string, dest: string): Promise<void> {
    if (fs.accessSync(dest)) {
      return;
    }
    const data: Uint8Array = await this.context.resourceManager.getRawFileContent(asset);
    const file = fs.openSync(dest, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, data.buffer as ArrayBuffer);
    } finally {
      fs.closeSync(file);
    }
    hilog.info(0x0000, TAG, 'extracted %{public}s (%{public}d bytes)', asset, data.length);
  }

  private async prepare(): Promise<void> {
    if (!fs.accessSync(this.vmDir)) {
      fs.mkdirSync(this.vmDir, true);
    }
    const shareDir: string = this.vmDir + '/share';
    if (!fs.accessSync(shareDir)) {
      fs.mkdirSync(shareDir, true);
    }
    await this.ensureFile(KERNEL_ASSET, this.vmDir + '/kernel_aarch64');
    await this.ensureFile(ROOTFS_ASSET, this.vmDir + '/rootfs_aarch64.qcow2');
  }

  /** 启动本机引擎，返回 baseUrl + token。 */
  async start(): Promise<LocalEngineInfo> {
    const missing: string = await this.checkAssets();
    if (missing.length > 0) {
      throw new LocalEngineError('assets/missing', missing);
    }
    await this.prepare();

    const kernel: string = this.vmDir + '/kernel_aarch64';
    const rootfs: string = this.vmDir + '/rootfs_aarch64.qcow2';
    let error: string = '';
    try {
      error = vmhost.vmStart(kernel, rootfs, ENGINE_PORT);
    } catch (e) {
      const err = e as BusinessError;
      throw new LocalEngineError('native/crash', `原生桥调用失败：${err.message}`);
    }
    if (error.length > 0) {
      throw new LocalEngineError('vm/start', error);
    }

    const token: string = await this.waitForToken();
    const info = new LocalEngineInfo();
    info.baseUrl = `http://127.0.0.1:${ENGINE_PORT}`;
    info.token = token;
    return info;
  }

  /** VM 里的 dsh web 会把启动 token 写进共享目录，这里轮询等它出现。 */
  private async waitForToken(): Promise<string> {
    const deadline: number = Date.now() + TOKEN_WAIT_MS;
    while (Date.now() < deadline) {
      if (fs.accessSync(this.tokenPath)) {
        const text: string = readText(this.tokenPath).trim();
        if (text.length > 0) {
          return text;
        }
      }
      await sleep(500);
    }
    throw new LocalEngineError(
      'vm/token-timeout',
      '等不到引擎 token（90 秒）。VM 可能没起来，详见 docs/LOCAL-ENGINE.md 的排障段。'
    );
  }

  stop(): void {
    try {
      vmhost.vmStop();
    } catch (e) {
      hilog.warn(0x0000, TAG, 'vmStop failed');
    }
  }
}

function readText(path: string): string {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const size: number = fs.statSync(path).size;
    const buffer = new ArrayBuffer(size);
    fs.readSync(file.fd, buffer);
    const bytes = new Uint8Array(buffer);
    let out: string = '';
    for (let i = 0; i < bytes.length; i++) {
      if (bytes[i] === 0) {
        break;
      }
      out += String.fromCharCode(bytes[i]);
    }
    return out;
  } finally {
    fs.closeSync(file);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}
