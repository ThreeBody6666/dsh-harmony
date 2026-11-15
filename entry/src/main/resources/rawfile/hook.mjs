// 引擎预加载钩子（node --import）：在 dsh 入口执行**之前**装好鸿蒙端兼容层。
//
// 为什么需要这一层（照 DSHM 的实现搬的，MIT）：
//   1. dsh 核心树里有几个 Node-API 原生插件只有 darwin/linux/win32 的预编译，
//      鸿蒙上没有对应平台包 → require 直接抛 "No usable native binding found"；
//   2. --jitless 关掉了 WASM，Node 内建 undici 初始化就用 WASM 版 llhttp → 一加载就炸；
//   3. 内建模块的 require 不走 Module._load，必须在 BuiltinModule 层预置 exports。
// 这三件事都由 compat/jitless-env.cjs 处理，必须在任何 dsh 代码之前生效。
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const log = (m) => {
  try {
    console.error('[dshgo-hook] ' + m);
  } catch {}
};

const home = process.env.DSH_HOME || process.cwd();
try {
  fs.mkdirSync(home, { recursive: true });
} catch {}

log('pid=' + process.pid + ' exposeInternals=' + process.execArgv.join(','));

try {
  const env = require(path.join(here, 'compat', 'jitless-env.cjs'));
  const libsDir = process.env.DSHGO_NATIVE_LIBS || '';
  if (typeof env.installNativeRedirect === 'function') {
    env.installNativeRedirect({ libsDir, log });
  }
  if (typeof env.installRequireBuiltinShim === 'function') {
    env.installRequireBuiltinShim(log);
  }
  if (typeof env.installInternalUndiciShim === 'function') {
    env.installInternalUndiciShim(log);
  }
  if (typeof env.installJitlessFetch === 'function') {
    env.installJitlessFetch(log);
  }
  log('compat 安装完成');
} catch (e) {
  log('compat 安装失败：' + String(e));
}
