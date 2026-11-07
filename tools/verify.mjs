#!/usr/bin/env node
/**
 * dsh-harmony 工程自检（不需要鸿蒙 SDK，纯静态检查）：
 *   1. 所有 *.json5 能被解析（去注释 / 尾逗号后按 JSON 解析）
 *   2. .ets 里的相对 import 都能落到真实文件
 *   3. 资源引用（$string: / $media: / $color: / $profile:）在 resources 里存在
 *   4. main_pages 里登记的页面文件存在，且各页面有 @Entry
 *   5. .ets 大括号/圆括号配平
 *
 * 用法：node tools/verify.mjs
 */

import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const errors = [];
const warnings = [];
let checked = 0;

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === '.git' || entry.name === 'build') continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}


/** 去掉注释与字符串内容，只留下代码骨架，供括号配平判断。 */
function codeOnly(text) {
  let out = '';
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    const next = text[i + 1];
    if (ch === '/' && next === '/') {
      while (i < text.length && text[i] !== '\n') i++;
      continue;
    }
    if (ch === '/' && next === '*') {
      i += 2;
      while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) i++;
      i += 2;
      continue;
    }
    if (ch === "'" || ch === '"' || ch === '`') {
      const quote = ch;
      i++;
      while (i < text.length && text[i] !== quote) {
        if (text[i] === '\\') i++;
        i++;
      }
      i++;
      out += '@';
      continue;
    }
    out += ch;
    i++;
  }
  return out;
}

function stripJson5(text) {
  let out = '';
  let i = 0;
  let inString = false;
  let quote = '';
  while (i < text.length) {
    const ch = text[i];
    const next = text[i + 1];
    if (inString) {
      out += ch;
      if (ch === '\\') {
        out += next ?? '';
        i += 2;
        continue;
      }
      if (ch === quote) inString = false;
      i++;
      continue;
    }
    if (ch === '"' || ch === "'") {
      inString = true;
      quote = ch;
      out += ch;
      i++;
      continue;
    }
    if (ch === '/' && next === '/') {
      while (i < text.length && text[i] !== '\n') i++;
      continue;
    }
    if (ch === '/' && next === '*') {
      i += 2;
      while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) i++;
      i += 2;
      continue;
    }
    out += ch;
    i++;
  }
  return out.replace(/,(\s*[}\]])/g, '$1');
}

const files = walk(ROOT);
const json5Files = files.filter((f) => f.endsWith('.json5'));
for (const file of json5Files) {
  const rel = path.relative(ROOT, file);
  try {
    JSON.parse(stripJson5(fs.readFileSync(file, 'utf8')));
    checked++;
  } catch (e) {
    errors.push(`JSON5 解析失败 ${rel}: ${e.message}`);
  }
}

// --- 资源表 ---
const resRoot = path.join(ROOT, 'entry/src/main/resources');
const appResRoot = path.join(ROOT, 'AppScope/resources');
const resources = { string: new Set(), color: new Set(), media: new Set(), profile: new Set() };
function loadRes(dir) {
  if (!fs.existsSync(dir)) return;
  for (const f of walk(dir)) {
    const rel = path.relative(dir, f);
    const m = rel.match(/base\/([a-z]+)\/([^/]+)$/);
    if (!m) continue;
    const [, kind, name] = m;
    if (kind === 'element') {
      try {
        const data = JSON.parse(stripJson5(fs.readFileSync(f, 'utf8')));
        for (const key of Object.keys(data)) {
          for (const item of data[key]) resources[key]?.add(item.name);
        }
      } catch (e) {
        errors.push(`资源文件解析失败 ${path.relative(ROOT, f)}: ${e.message}`);
      }
    } else if (kind === 'media') {
      resources.media.add(name.replace(/\.[^.]+$/, ''));
    } else if (kind === 'profile') {
      resources.profile.add(name.replace(/\.[^.]+$/, ''));
    }
  }
}
loadRes(resRoot);
loadRes(appResRoot);

// --- .ets 检查 ---
const etsFiles = files.filter((f) => f.endsWith('.ets'));
for (const file of etsFiles) {
  const rel = path.relative(ROOT, file);
  const src = fs.readFileSync(file, 'utf8');

  // import 解析
  const importRe = /^\s*import\s+[^;]*?from\s+['"]([^'"]+)['"]\s*;?/gm;
  let m;
  while ((m = importRe.exec(src)) !== null) {
    const spec = m[1];
    if (!spec.startsWith('.')) continue; // 系统 kit
    const base = path.resolve(path.dirname(file), spec);
    const candidates = [base, base + '.ets', base + '.ts', path.join(base, 'index.ets')];
    if (!candidates.some((c) => fs.existsSync(c))) {
      errors.push(`import 解析失败 ${rel}: '${spec}'`);
    }
  }

  // 资源引用
  const resRe = /\$([a-z]+):([A-Za-z0-9_]+)/g;
  while ((m = resRe.exec(src)) !== null) {
    const [, kind, name] = m;
    if (resources[kind] && !resources[kind].has(name)) {
      warnings.push(`资源引用可能不存在 ${rel}: $${kind}:${name}`);
    }
  }

  // 括号配平（按字符扫描，字符串与注释内的括号不计）
  const cleaned = codeOnly(src);
  for (const [open, close, label] of [['{', '}', '大括号'], ['(', ')', '圆括号'], ['[', ']', '方括号']]) {
    const a = (cleaned.match(new RegExp('\\' + open, 'g')) || []).length;
    const b = (cleaned.match(new RegExp('\\' + close, 'g')) || []).length;
    if (a !== b) errors.push(`${label}不配平 ${rel}: ${a} vs ${b}`);
  }
  checked++;
}

// --- 页面登记 ---
const mainPagesFile = path.join(resRoot, 'base/profile/main_pages.json');
if (fs.existsSync(mainPagesFile)) {
  const pages = JSON.parse(stripJson5(fs.readFileSync(mainPagesFile, 'utf8'))).src || [];
  for (const p of pages) {
    const f = path.join(ROOT, 'entry/src/main/ets', p + '.ets');
    if (!fs.existsSync(f)) {
      errors.push(`main_pages 登记的页面不存在: ${p}`);
      continue;
    }
    if (!/@Entry/.test(fs.readFileSync(f, 'utf8'))) {
      errors.push(`页面缺少 @Entry: ${p}`);
    }
  }
} else {
  errors.push('缺少 resources/base/profile/main_pages.json');
}

// --- module.json5 必需字段 ---
const moduleFile = path.join(ROOT, 'entry/src/main/module.json5');
if (fs.existsSync(moduleFile)) {
  const mod = JSON.parse(stripJson5(fs.readFileSync(moduleFile, 'utf8'))).module;
  for (const key of ['name', 'type', 'mainElement', 'deviceTypes', 'pages', 'abilities']) {
    if (mod[key] === undefined) errors.push(`module.json5 缺少字段: ${key}`);
  }
  if (mod.type !== 'entry') errors.push('module.json5 type 必须是 entry');
  const perms = (mod.requestPermissions || []).map((p) => p.name);
  if (!perms.includes('ohos.permission.INTERNET')) errors.push('module.json5 缺少 ohos.permission.INTERNET');
} else {
  errors.push('缺少 entry/src/main/module.json5');
}

const appFile = path.join(ROOT, 'AppScope/app.json5');
if (fs.existsSync(appFile)) {
  const app = JSON.parse(stripJson5(fs.readFileSync(appFile, 'utf8'))).app;
  for (const key of ['bundleName', 'versionCode', 'versionName', 'icon', 'label']) {
    if (app[key] === undefined) errors.push(`app.json5 缺少字段: ${key}`);
  }
} else {
  errors.push('缺少 AppScope/app.json5');
}

// --- 原生桥一致性 ---
const cppDir = path.join(ROOT, 'entry/src/main/cpp');
const cmakeFile = path.join(cppDir, 'CMakeLists.txt');
if (!fs.existsSync(cmakeFile)) {
  errors.push('缺少 entry/src/main/cpp/CMakeLists.txt');
} else {
  const cmake = fs.readFileSync(cmakeFile, 'utf8');
  const libMatch = cmake.match(/add_library\((\w+)\s+SHARED/);
  if (!libMatch) errors.push('CMakeLists.txt 没有 add_library(<name> SHARED ...)');
  const libName = libMatch ? 'lib' + libMatch[1] + '.so' : '';
  // ArkTS 里 import 的原生模块名必须与 CMake 产物一致
  for (const file of etsFiles) {
    const src = fs.readFileSync(file, 'utf8');
    const nativeImport = src.match(/import\s+\w+\s+from\s+['"]([\w.-]+\.so)['"]/);
    if (nativeImport && libName && nativeImport[1] !== libName) {
      errors.push(`原生模块名不匹配 ${path.relative(ROOT, file)}: import '${nativeImport[1]}' 但 CMake 产出 ${libName}`);
    }
  }
  for (const need of ['napi_init.cpp', 'vm_host.h', 'vm_host_stub.cpp']) {
    if (!fs.existsSync(path.join(cppDir, need))) errors.push(`cpp 目录缺少 ${need}`);
  }
  if (!fs.existsSync(path.join(cppDir, 'vendor/qemu'))) {
    warnings.push('缺少 cpp/vendor/qemu/ 目录（有 qemu 库时才会编真实现）');
  }
}
if (!fs.existsSync(path.join(ROOT, 'entry/src/main/resources/rawfile/vm'))) {
  warnings.push('缺少 rawfile/vm/ 目录（本机模式需要内核与 rootfs）');
}

const etsCount = etsFiles.length;
const lines = etsFiles.reduce((n, f) => n + fs.readFileSync(f, 'utf8').split('\n').length, 0);
console.log(`检查文件 ${checked} 个（.ets ${etsCount} 个 / ${lines} 行，.json5 ${json5Files.length} 个）`);
if (warnings.length) {
  console.log(`\n警告 ${warnings.length} 条：`);
  for (const w of warnings) console.log('  ⚠ ' + w);
}
if (errors.length) {
  console.log(`\n错误 ${errors.length} 条：`);
  for (const e of errors) console.log('  ✗ ' + e);
  process.exit(1);
}
console.log('\n✓ 静态检查通过');
