// 引擎输出钩子：通过 node --import 预加载，把 stdout/stderr 落盘。
//
// 为什么不用 bootstrap 脚本 import 引擎：dsh 的入口会判断「自己是不是主模块」
// （比较 import.meta.url 与 argv[1]），被 import 时不会执行 main。所以改成
// 「预加载钩子 + 正常启动入口」。
import fs from 'node:fs';
import path from 'node:path';

const home = process.env.DSH_HOME || process.cwd();
const logPath = path.join(home, 'engine.log');
try {
  fs.mkdirSync(home, { recursive: true });
  fs.appendFileSync(logPath, `[hook] pid=${process.pid}\n`);
} catch {}

function wrap(writer) {
  return (...args) => {
    try {
      const chunk = args[0];
      fs.appendFileSync(logPath, typeof chunk === 'string' ? chunk : Buffer.from(chunk));
    } catch {}
    return writer(...args);
  };
}
process.stdout.write = wrap(process.stdout.write.bind(process.stdout));
process.stderr.write = wrap(process.stderr.write.bind(process.stderr));
