# 工程与协议说明（附实测记录）

本文件记录鸿蒙端用到的引擎协议，以及验证方式。协议事实来自 dsh-go 仓库的
`packages/dsh_client`（Dart），并在本机独立 `dsh web` 实例上逐条实测过。

---

## 1. 连接

```
GET /?token=<启动 token>
```

- 引擎返回 `303` 并下发 `Set-Cookie: dsh-auth-<base64url(sha256(authority))>=v1.<payload>.<signature>`
- cookie 绑定 `host:port`，默认 30 天有效；`GET /?token=` 是唯一的换票入口
- 后续所有请求带 `Cookie: <name>=<value>`，**不要**带 `Origin`
- 浏览器护栏：只接受 loopback 或 `--trusted-host` 列出的 authority；跨站 `sec-fetch-site` 直接拒

实测（2026-11-07，本机 `dsh web --port 3099`）：

```
login status 303, set-cookie count 1
cookieName dsh-auth-3BwAN0…（base64url(sha256("127.0.0.1:3099"))）
cookieLen 224
```

## 2. 单次调用（HTTP）

```
POST /api/<endpoint>
content-type: application/json

{"type":"client-request","rpcId":"<uuid>","method":"<endpoint>","payload":{"args":{...}}}
```

响应恒为 HTTP 200 + `{type:"server-response", rpcId, result:{ok, value?, error?}}`。
业务错误是 `ok:false`；只有载体级拒绝才用 401/403/404/415。

注意：`args` 的键名要严格匹配 typert 描述符，例如
`session/follow`、`session/page`、`session/prompt` 的入参都包了一层 `request`，
而 `session/list` 用 `_request`。

## 3. 流式调用（WebSocket）

```
WS /api/remote.mux        （一帧一条 JSON 文本）
client → host  {"type":"open","streamId","endpoint","payload":{"args":{...}}}
               {"type":"item","streamId","value"}
               {"type":"end","streamId"}
               {"type":"cancel","streamId"}
host → client  {"type":"item","streamId","value"}
               {"type":"end","streamId"}
               {"type":"error","streamId","error":{code,message,details}}
```

每个连接世代必须先开 `$events` 流（`payload:{args:{}}`），首帧：

```json
{"type":"ready","clientId":"…","host":{"home":"/root"}}
```

拿到 ready 之后才能开 `session/follow`，否则行为未定义。

实测：`open` 时 `payload` 必须是 `{args:{…}}`，直接给 `{address:…}` 会得到
`gateway/internal: Remote payload must contain exactly one plain-object args field`。

## 4. 会话关注（session/follow）

```json
{"request":{
  "address":{"kind":"session","sessionId":"…"},
  "assistantStream":true,
  "maxMessages":500,
  "turnWindow":{"minMessages":50,"minTurns":2}
}}
```

流里的 item 有三类：

| 帧 | 结构 |
|---|---|
| 首帧 | `{"type":"snapshot","header":{…},"projections":{asOfSeq,values},"cursor":548,"records":[{type:"event",event}],"hasMore":true,"assistantStream":{revision}}` |
| 持久事件 | `{"type":"event","event":{"type":"user/message","seq":225,"time":…,"data":{…}}}` |
| 增量 | `{"type":"assistant-stream","frame":{"type":"chunk","chunk":{"type":"text-delta","text":"收到"}}}` |

增量帧的 `frame.type` 有 `start` / `chunk` / `end`，chunk 子类型有
`block-start` / `text-delta` / `reasoning-delta` / `tool-call-delta` / `block-end` / `usage` / `finish`。

### 事件 `data` 的关键形状（实测）

```jsonc
// user/message —— 只有 source.kind === "user" 才是用户真实发言
{"content":[{"type":"text","text":"…"}],
 "source":{"kind":"user","rpcId":"…"},"role":"user","id":"…"}

// 注入型上下文（默认不显示）：time-context / runtime-context / skill-catalog / tool-jobs / user-approval

// assistant/message
{"turn":1,"step":1,"message":{"role":"assistant","content":[
  {"type":"reasoning","text":"…"},{"type":"text","text":"收到"},
  {"type":"tool-call","id":"call_x","name":"bash","arguments":"{…}"}]}}

// tool/call
{"turn":7,"step":11,"callId":"call_…","name":"bash","arguments":"{…}"}

// tool/result —— toolCallId 在 message 里，不在 data 上
{"turn":7,"step":11,"message":{"role":"tool",
  "source":{"kind":"tool","callId":"call_…"},
  "toolCallId":"call_…","isError":false,
  "content":[{"type":"text","text":"…"}]}}

// turn/end
{"turn":7,"reason":{"kind":"interrupted"}}   // completed / interrupted / error
```

这两处是踩过的坑：`toolCallId` 在 `message` 里、`isError` 也在 `message` 里；
一开始写在 `data` 上，导致工具卡片永远停在「运行中」。

## 5. 发送与中断

```jsonc
// session/prompt
{"request":{"requestId":"<uuid>","sessionId":"…","mode":"queue",
            "content":[{"type":"text","text":"…"}]}}
// → {"ok":true,"value":{"accepted":true}}；requestId 会回显在 user/message.source.rpcId

// session/cancel
{"request":{"sessionId":"…"}}
```

## 6. 历史翻页

```jsonc
{"request":{"address":{"kind":"session","sessionId":"…"},
            "throughSeq":548,"beforeSeq":200,"maxMessages":200}}
// → {"records":[{type:"event",event}],"hasMore":true}
```

`throughSeq` 用你当前持有的最新 seq；越界会报 `gateway/input-invalid`
（`boundary validation`）。鸿蒙端首版只用 follow 的首帧 snapshot，翻页接口已留好。

## 7. 已知行为

- 断线重连后必须重开 follow，靠首帧 snapshot 全量重同步；不要试图续接旧 seq。
- `$events` 流在世代切换时旧流作废，`clientId` 也会变。
- 引擎每 2 秒 ping 一次 WebSocket。
