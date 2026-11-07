#!/usr/bin/env node
/**
 * 把工程推到 GitHub 并等云端编译结果。
 *
 * 用法：
 *   GITHUB_TOKEN=<pat> node scripts/ci-push.mjs [--repo dsh-harmony] [--private]
 *
 * 做四件事：
 *   1. 用 token 换出账号名，确认权限够
 *   2. 仓库不存在就创建（默认公开）
 *   3. 推送 main 分支，触发 Actions
 *   4. 轮询这次 commit 的运行状态，结束时打印结论；失败就把日志要点打出来
 *
 * 安全：token 只从环境变量读，不落盘、不打印。
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const API = 'https://api.github.com';
const token = process.env.GITHUB_TOKEN;

if (!token) {
  console.error('缺少 GITHUB_TOKEN 环境变量');
  process.exit(2);
}

const argv = process.argv.slice(2);
const repoName = argv.includes('--repo') ? argv[argv.indexOf('--repo') + 1] : 'dsh-harmony';
const isPrivate = argv.includes('--private');

async function api(method, endpoint, body) {
  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      const res = await fetch(API + endpoint, {
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/vnd.github+json',
          'User-Agent': 'dsh-harmony-ci',
          'X-GitHub-Api-Version': '2022-11-28',
          ...(body ? { 'Content-Type': 'application/json' } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
      });
      const text = await res.text();
      const data = text ? JSON.parse(text) : {};
      if (!res.ok && res.status !== 404) {
        throw new Error(`${method} ${endpoint} -> ${res.status} ${data.message || text.slice(0, 200)}`);
      }
      return { status: res.status, data };
    } catch (e) {
      if (attempt === 4) throw e;
      await new Promise((r) => setTimeout(r, 2000 * attempt));
    }
  }
}

function git(args, opts = {}) {
  return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', ...opts });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 1) 账号
const me = await api('GET', '/user');
const owner = me.data.login;
console.log(`✓ 账号：${owner}`);

const scopes = (await fetch(API + '/user', { headers: { Authorization: `Bearer ${token}` } })).headers.get('x-oauth-scopes');
if (scopes !== null) console.log(`  token scopes: ${scopes || '(无)'}`);

// 2) 仓库
const repoPath = `/${owner}/${repoName}`;
const existing = await api('GET', `/repos${repoPath}`);
let repoUrl;
if (existing.status === 200) {
  console.log(`✓ 仓库已存在：${existing.data.html_url}`);
  repoUrl = existing.data.clone_url;
} else {
  const created = await api('POST', '/user/repos', {
    name: repoName,
    private: isPrivate,
    description: 'dsh-go 鸿蒙端：ArkTS 客户端 + 云端编译流水线',
    auto_init: false,
  });
  console.log(`✓ 已创建仓库：${created.data.html_url}`);
  repoUrl = created.data.clone_url;
}

// 3) 推送
// 注意：不要在 remote 配置里写 token（中断会残留）。这里用一次性 URL。
const authUrl = repoUrl.replace('https://', `https://x-access-token:${token}@`);
const branch = git(['rev-parse', '--abbrev-ref', 'HEAD']).trim();
console.log(`→ 推送 ${branch} 到 ${owner}/${repoName} …`);
git(['push', authUrl, `${branch}:${branch}`], { stdio: 'pipe' });
const sha = git(['rev-parse', 'HEAD']).trim();
console.log(`✓ 推送完成 ${sha.slice(0, 7)}`);

// 4) 等构建
console.log('→ 等待 Actions 启动 …');
let runId = null;
for (let i = 0; i < 30 && runId === null; i++) {
  await sleep(4000);
  const runs = await api('GET', `/repos${repoPath}/actions/runs?head_sha=${sha}&per_page=5`);
  const run = (runs.data.workflow_runs || [])[0];
  if (run) runId = run.id;
}
if (runId === null) {
  console.log('没等到运行记录，去仓库 Actions 页看看：' + `https://github.com${repoPath}/actions`);
  process.exit(0);
}
console.log(`✓ 运行已启动：https://github.com${repoPath}/actions/runs/${runId}`);

let conclusion = null;
for (let i = 0; i < 150; i++) {
  await sleep(6000);
  const run = await api('GET', `/repos${repoPath}/actions/runs/${runId}`);
  const status = run.data.status;
  if (status === 'completed') {
    conclusion = run.data.conclusion;
    break;
  }
  if (i % 10 === 0) console.log(`  … 仍在构建（${status}）`);
}

console.log(`\n结论：${conclusion === null ? '未完成（超时）' : conclusion}`);
if (conclusion === 'success') {
  const arts = await api('GET', `/repos${repoPath}/actions/runs/${runId}/artifacts`);
  for (const a of arts.data.artifacts || []) {
    console.log(`  产物：${a.name} (${Math.round(a.size_in_bytes / 1024)} KB)`);
  }
  console.log(`  下载页：https://github.com${repoPath}/actions/runs/${runId}`);
} else if (conclusion !== null) {
  console.log('构建失败，日志要点：');
  const jobs = await api('GET', `/repos${repoPath}/actions/runs/${runId}/jobs`);
  for (const job of jobs.data.jobs || []) {
    console.log(`\n## ${job.name} — ${job.conclusion}`);
    for (const step of job.steps || []) {
      const mark = step.conclusion === 'failure' ? '✗' : step.conclusion === 'success' ? '✓' : '·';
      console.log(`  ${mark} ${step.name}`);
    }
  }
}
