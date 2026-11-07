# 鸿蒙 API 核对笔记（本工程实际用到的）

> 说明：原本派了一个子任务去核对官方文档，但那个任务中途失败、没有产出。
> 下面是本工程实际用到的 API 与核对情况，标注「已核对」的都对着官方示例/文档确认过。

## 1. 网络

| 用途 | 写法 | 状态 |
|---|---|---|
| HTTP | `import { http } from '@kit.NetworkKit';` + `http.createHttp()` | 已核对（API 12 Kit 化导入） |
| WebSocket | `import { webSocket } from '@kit.NetworkKit';` + `webSocket.createWebSocket()` | 已核对 |
| WS 连接 | `ws.connect(url, { header: Record<string,string> })` | 已核对：`WebSocketRequestOptions.header` |
| WS 事件 | `on('open', (err: BusinessError, value: Object))`、`on('message', (err, value: string \| ArrayBuffer))`、`on('close', (err, value: webSocket.CloseResult))`、`on('error', (err: BusinessError))` | 已核对：[官方论坛示例](https://forums.developer.huawei.com/forumPortal/en/topic/0205201443703317097)、[博客示例](https://www.cnblogs.com/webabcd/p/18789398/harmony_pages_network_WebSocketDemo) 用的都是 `webSocket.CloseResult` |
| HTTP 响应 cookie | `HttpResponse.cookies: string` | 已核对存在；另加 `header['set-cookie']` 与响应体三重兜底 |
| 自定义请求头 | `header: Record<string, string>`，可写 `Cookie` | 已核对；**能否覆盖 `Host` 头未确认**，所以远程接入不靠改 Host，改用引擎的 `--trusted-host` |

## 2. 存储

```ts
import { preferences } from '@kit.ArkData';
const store = await preferences.getPreferences(context, { name: 'dshgo' });
store.getSync(key, def); store.putSync(key, val); store.flush(); store.deleteSync(key);
```
`getPreferences` 需要 `Context`（`UIAbility.context`）。明文存 cookie，后续应换
`@ohos.security.asset`。

## 3. 工程配置

- `AppScope/app.json5`：`bundleName` / `versionCode` / `versionName` / `icon` / `label`
- `entry/src/main/module.json5`：`name` / `type: entry` / `mainElement` / `deviceTypes` /
  `pages` / `abilities` / `requestPermissions`
- 权限：`ohos.permission.INTERNET`（normal 级，声明即可，不需要弹窗）；
  另声明了 `ohos.permission.GET_NETWORK_INFO` 用于判断网络状态
- 局域网明文 HTTP：鸿蒙没有 Android 9 那种全局 cleartext 限制，`@ohos.net.http`
  直连 `http://192.168.x.x:3080` 可用；如果用 `Web` 组件加载网页则另需注意混合内容策略（本工程暂未用 Web 组件）
- `build-profile.json5` 里 `compileSdkVersion: 12` / `compatibleSdkVersion: 12` /
  `runtimeOS: "HarmonyOS"`；若你的 DevEco 用字符串写法（如 `"5.0.0(12)"`），按 IDE 新建工程的模板改回字符串即可

## 4. ArkTS 严格模式的坑（本工程已规避）

| 坑 | 规避方式 |
|---|---|
| 不允许 `any` / `unknown` | 全量显式接口，动态 JSON 用 `Record<string, Object>` |
| `Object` 上不能直接取键 | 先 `as Record<string, Object>` 再取 |
| 对象字面量必须有明确类型 | 模块级常量 + 显式标注（如 `const EMPTY_EVENT_DATA: EventDataRaw = {}`） |
| 双重断言 `x as Object as T` 不稳 | 拆成「先取 `Object \| undefined` → 判空 → 单次 `as T`」 |
| 回调参数类型要精确 | `on('close')` 用 `webSocket.CloseResult`，不用 `Object` |
| `@Prop` 对类实例是深拷贝语义、不追踪内部变更 | 聊天行组件全部用基本类型入参，父组件换数组触发刷新 |
| `@Builder` 参数按值传递 | 标题/返回态都作为参数传入 |
| 局部变量在自身初始化回调里引用 | 先声明 `holder` 再赋值（见 `Index.openSession`） |

## 5. 编译期待确认项（本机没有 SDK，无法编译）

1. `@kit.NetworkKit` 的 Kit 化导入是否与你的 SDK 版本匹配（API 12 起可用；更早用 `@ohos.net.http` / `@ohos.net.webSocket`）
2. `Record<string, Object>` 在 `resp.header` 上的取键断言
3. `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])` 的参数形态
4. `TextInput({ text })` 受控写法在长会话下的光标行为
5. `preferences` 的 `getSync/putSync` 是否需要 `flush()` 才算落盘（已在写后调用）

真机编译时如果报错，按 `docs/BUILD.md` 第七节的对照表改，基本都是导入路径和类型断言两类。
