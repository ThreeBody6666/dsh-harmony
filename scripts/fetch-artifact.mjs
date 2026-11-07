#!/usr/bin/env node
// 下载某次 Actions 运行的 hap-unsigned 产物，并解出 HAP。
// 用法: GITHUB_TOKEN=xxx node scripts/fetch-artifact.mjs <artifact_id> <out.hap>
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [artifactId, outHap] = process.argv.slice(2);
const token = process.env.GITHUB_TOKEN;
if (!artifactId || !outHap || !token) {
  console.error('用法: GITHUB_TOKEN=... node fetch-artifact.mjs <artifact_id> <out.hap>');
  process.exit(2);
}
const repo = process.env.REPO || 'ThreeBody6666/dsh-harmony';

async function download(zipPath) {
  const res = await fetch(`https://api.github.com/repos/${repo}/actions/artifacts/${artifactId}/zip`, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'User-Agent': 'ci' },
    redirect: 'follow',
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const ws = fs.createWriteStream(zipPath);
  let n = 0;
  for await (const chunk of res.body) {
    ws.write(chunk);
    n += chunk.length;
    if (n % (64 * 1024 * 1024) < chunk.length) console.log(`${(n / 1048576).toFixed(0)}MB`);
  }
  await new Promise((r) => ws.end(r));
  return n;
}

let zipPath = '/tmp/hap-artifact.zip';
for (let attempt = 1; attempt <= 4; attempt++) {
  try {
    const size = await download(zipPath);
    console.log('downloaded', (size / 1048576).toFixed(0), 'MB');
    break;
  } catch (e) {
    console.log(`第 ${attempt} 次失败: ${e.message}`);
    if (attempt === 4) process.exit(1);
  }
}

// 解出 HAP（用 python 的 zipfile，Node 没有内置 zip 解压）
const { execFileSync } = await import('node:child_process');
execFileSync('python3', ['-c', `
import zipfile, sys, shutil
z = zipfile.ZipFile(${JSON.stringify(zipPath)})
name = [n for n in z.namelist() if n.endswith('.hap')][0]
with z.open(name) as src, open(${JSON.stringify(outHap)}, 'wb') as dst:
    shutil.copyfileobj(src, dst)
print('hap:', name)
`], { stdio: 'inherit' });
console.log('saved', outHap, (fs.statSync(outHap).size / 1048576).toFixed(0), 'MB');
