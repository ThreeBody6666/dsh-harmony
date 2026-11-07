#!/usr/bin/env node
// 拉取最近一次失败的 Actions 运行日志到 /tmp/ci.log
import fs from 'node:fs';
const token = process.env.GITHUB_TOKEN;
const repo = process.env.REPO || 'ThreeBody6666/dsh-harmony';
if (!token) { console.error('缺少 GITHUB_TOKEN'); process.exit(2); }
const H = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'User-Agent': 'ci' };
const runs = await (await fetch(`https://api.github.com/repos/${repo}/actions/runs?per_page=5`, { headers: H })).json();
const run = runs.workflow_runs[0];
console.log('run', run.id, run.conclusion, run.head_sha.slice(0, 7));
const jobs = await (await fetch(`https://api.github.com/repos/${repo}/actions/runs/${run.id}/jobs`, { headers: H })).json();
const job = (jobs.jobs || []).find((j) => j.conclusion === 'failure') || (jobs.jobs || [])[0];
const res = await fetch(`https://api.github.com/repos/${repo}/actions/jobs/${job.id}/logs`, { headers: H, redirect: 'follow' });
const text = await res.text();
fs.writeFileSync('/tmp/ci.log', text);
console.log('job', job.name, '-> /tmp/ci.log', text.length, 'bytes');
