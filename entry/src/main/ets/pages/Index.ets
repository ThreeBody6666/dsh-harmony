/**
 * DSH Go 鸿蒙端主页面。
 *
 * 单页三分支（不依赖 router，降低 API 风险）：
 *   connect  —— 填引擎地址 + 启动 token，登录
 *   sessions —— 会话列表
 *   chat     —— 聊天（session/follow 实时流）
 */

import { ChatRow } from '../ui/ChatRows';
import { LocalEngine, LocalEngineError, LocalEngineInfo } from '../client/LocalEngine';
import { common } from '@kit.AbilityKit';
import { Theme, timeLabel } from '../ui/Theme';
import { Store } from '../ui/Storage';
import { DshClient, SessionWatch } from '../client/DshClient';
import { ChatItem, SessionRow } from '../model/Types';
import { DshError } from '../net/Connection';

@Entry
@Component
struct Index {
  @State stage: string = 'connect';
  @State baseUrl: string = 'http://127.0.0.1:3080';
  @State token: string = '';
  @State status: string = '';
  @State errorText: string = '';
  @State sessions: SessionRow[] = [];
  @State items: ChatItem[] = [];
  @State draft: string = '';
  @State busy: boolean = false;
  @State currentTitle: string = '';
  @State currentId: string = '';

  private client: DshClient | null = null;
  private watch: SessionWatch | null = null;
  private localEngine: LocalEngine | null = null;

  aboutToAppear(): void {
    this.restore();
  }

  aboutToDisappear(): void {
    this.detach();
    this.stopLocalEngine();
  }

  private stopLocalEngine(): void {
    if (this.localEngine !== null) {
      const engine: LocalEngine = this.localEngine;
      this.localEngine = null;
      engine.stop();
    }
  }

  private async restore(): Promise<void> {
    const url: string = await Store.get('baseUrl', '');
    const token: string = await Store.get('token', '');
    if (url.length > 0) {
      this.baseUrl = url;
    }
    if (token.length > 0) {
      this.token = token;
    }
  }

  /** 本机模式：在手机里起 VM，拿到 127.0.0.1 的引擎后走同一条登录链路。 */
  private async startLocal(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    this.status = '检查本机资源…';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const engine = new LocalEngine(context);
      this.localEngine = engine;
      this.status = '启动虚拟机…';
      const info: LocalEngineInfo = await engine.start();
      this.baseUrl = info.baseUrl;
      this.token = info.token;
      this.status = '登录本机引擎…';
      await this.connectWith(info.baseUrl, info.token);
    } catch (e) {
      if (e instanceof LocalEngineError) {
        this.errorText = (e as LocalEngineError).code + '：' + (e as LocalEngineError).message;
      } else {
        const err = e as Error;
        this.errorText = err.message;
      }
      this.status = '';
    } finally {
      this.busy = false;
    }
  }

  /** 用指定地址登录（本机模式与手填地址共用）。 */
  private async connectWith(baseUrl: string, token: string): Promise<void> {
    const client: DshClient = await DshClient.login(baseUrl, token);
    this.client = client;
    await Store.put('baseUrl', baseUrl);
    await Store.put('token', token);
    this.sessions = await client.listSessions();
    this.stage = 'sessions';
    this.status = '';
  }

  private async connect(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    this.status = '正在登录…';
    try {
      const client: DshClient = await DshClient.login(this.baseUrl, this.token);
      this.client = client;
      await Store.put('baseUrl', this.baseUrl);
      await Store.put('token', this.token);
      const rows: SessionRow[] = await client.listSessions();
      this.sessions = rows;
      this.stage = 'sessions';
      this.status = '';
    } catch (e) {
      const err = e as Error;
      this.errorText = err.message;
      this.status = '';
    } finally {
      this.busy = false;
    }
  }

  private async refreshSessions(): Promise<void> {
    if (this.client === null) {
      return;
    }
    try {
      this.sessions = await this.client.listSessions();
    } catch (e) {
      const err = e as Error;
      this.errorText = err.message;
    }
  }

  private async newSession(): Promise<void> {
    if (this.client === null) {
      return;
    }
    try {
      const id: string = await this.client.createSession();
      await this.openSession(id, '新会话');
    } catch (e) {
      const err = e as Error;
      this.errorText = err.message;
    }
  }

  private detach(): void {
    if (this.watch !== null) {
      const w: SessionWatch = this.watch;
      this.watch = null;
      w.stop();
    }
  }

  private async openSession(sessionId: string, title: string): Promise<void> {
    if (this.client === null) {
      return;
    }
    this.detach();
    this.currentId = sessionId;
    this.currentTitle = title.length > 0 ? title : sessionId;
    this.items = [];
    this.stage = 'chat';
    const client: DshClient = this.client;
    // 回调里要引用 watch 自身，先声明再赋值，避免「使用前声明」的编译告警
    let holder: SessionWatch | null = null;
    const watch: SessionWatch = client.watch(
      sessionId,
      () => {
        if (holder === null) {
          return;
        }
        this.items = holder.transcript.items.slice();
        if (holder.transcript.title.length > 0) {
          this.currentTitle = holder.transcript.title;
        }
        this.busy = holder.transcript.running;
      },
      (text: string) => {
        this.status = text;
      }
    );
    holder = watch;
    this.watch = watch;
    await watch.start();
  }

  private async send(): Promise<void> {
    const text: string = this.draft.trim();
    if (text.length === 0 || this.client === null || this.currentId.length === 0) {
      return;
    }
    this.draft = '';
    this.errorText = '';
    try {
      await this.client.prompt(this.currentId, text);
    } catch (e) {
      const err = e as Error;
      this.errorText = err.message;
      if (e instanceof DshError) {
        this.errorText = (e as DshError).code + ': ' + (e as DshError).message;
      }
    }
  }

  private async stopTurn(): Promise<void> {
    if (this.client === null || this.currentId.length === 0) {
      return;
    }
    try {
      await this.client.cancel(this.currentId);
    } catch (e) {
      const err = e as Error;
      this.errorText = err.message;
    }
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @Builder
  header(title: string, back: boolean) {
    Row() {
      if (back) {
        Text('‹')
          .fontSize(26)
          .fontColor(Theme.text)
          .width(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.detach();
            this.stage = 'sessions';
            this.refreshSessions();
          })
      } else {
        Text('')
          .width(36)
      }
      Text(title)
        .fontSize(Theme.fontTitle)
        .fontColor(Theme.text)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.status.length > 0) {
        Text(this.status)
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.textFaint)
          .maxLines(1)
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 6, right: Theme.pad })
  }

  @Builder
  errorBar() {
    if (this.errorText.length > 0) {
      Row() {
        Text(this.errorText)
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.danger)
          .layoutWeight(1)
          .maxLines(3)
        Text('×')
          .fontSize(18)
          .fontColor(Theme.textDim)
          .padding({ left: 8 })
          .onClick(() => {
            this.errorText = '';
          })
      }
      .width('100%')
      .padding(10)
      .backgroundColor('#3A1E24')
      .margin({ left: Theme.pad, right: Theme.pad, bottom: 8 })
      .borderRadius(10)
    }
  }

  @Builder
  connectView() {
    Column() {
      Text('DSH Go')
        .fontSize(30)
        .fontColor(Theme.text)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 70, bottom: 6 })
      Text('鸿蒙客户端 · 先连上一台跑着 dsh web 的机器')
        .fontSize(Theme.fontSmall)
        .fontColor(Theme.textDim)
        .margin({ bottom: 26 })

      Column() {
        Text('引擎地址')
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.textDim)
          .width('100%')
          .margin({ bottom: 6 })
        TextInput({ text: this.baseUrl, placeholder: 'http://192.168.1.10:3080' })
          .type(InputType.Normal)
          .fontSize(Theme.fontBody)
          .fontColor(Theme.text)
          .placeholderColor(Theme.textFaint)
          .backgroundColor(Theme.card)
          .borderRadius(10)
          .onChange((v: string) => {
            this.baseUrl = v;
          })

        Text('启动 token')
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.textDim)
          .width('100%')
          .margin({ top: 16, bottom: 6 })
        TextInput({ text: this.token, placeholder: 'dsh web 启动时打印的 token' })
          .type(InputType.Password)
          .fontSize(Theme.fontBody)
          .fontColor(Theme.text)
          .placeholderColor(Theme.textFaint)
          .backgroundColor(Theme.card)
          .borderRadius(10)
          .onChange((v: string) => {
            this.token = v;
          })

        Button(this.busy ? '登录中…' : '连接')
          .width('100%')
          .height(46)
          .margin({ top: 24 })
          .backgroundColor(Theme.accent)
          .fontColor('#06121E')
          .borderRadius(12)
          .enabled(!this.busy)
          .onClick(() => {
            this.connect();
          })

        Button(this.busy ? '请稍候…' : '在手机本机启动引擎')
          .width('100%')
          .height(42)
          .margin({ top: 10 })
          .backgroundColor(Theme.card)
          .fontColor(Theme.textDim)
          .borderRadius(12)
          .enabled(!this.busy)
          .onClick(() => {
            this.startLocal();
          })
      }
      .width('100%')

      Column() {
        Text('本机模式 = 手机里跑一台 Linux 虚拟机，VM 内启动 dsh web；\n首版需要先把 kernel/镜像打进包里（见 docs/LOCAL-ENGINE.md）。')
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.textFaint)
          .width('100%')
          .margin({ bottom: 10 })
        Text('连电脑的话，电脑端这样启动：')
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.textDim)
          .width('100%')
        Text('dsh web --host 0.0.0.0 --trusted-host <手机访问的IP>:3080')
          .fontSize(Theme.monoSize)
          .fontColor(Theme.accent)
          .width('100%')
          .margin({ top: 6 })
      }
      .width('100%')
      .padding(12)
      .backgroundColor(Theme.bgElevated)
      .borderRadius(10)
      .margin({ top: 26 })
    }
    .width('100%')
    .padding({ left: Theme.pad + 4, right: Theme.pad + 4 })
  }

  @Builder
  sessionsView() {
    Column() {
      this.header('会话', false)
      this.errorBar()
      Row() {
        Button('新建会话')
          .height(38)
          .fontSize(Theme.fontSmall)
          .backgroundColor(Theme.accentSoft)
          .fontColor(Theme.text)
          .borderRadius(10)
          .onClick(() => {
            this.newSession();
          })
        Blank()
        Button('刷新')
          .height(38)
          .fontSize(Theme.fontSmall)
          .backgroundColor(Theme.card)
          .fontColor(Theme.textDim)
          .borderRadius(10)
          .onClick(() => {
            this.refreshSessions();
          })
      }
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, bottom: 8 })

      List() {
        ForEach(this.sessions, (row: SessionRow) => {
          ListItem() {
            Column() {
              Row() {
                Text(row.title.length > 0 ? row.title : row.sessionId.substring(0, 8))
                  .fontSize(Theme.fontBody)
                  .fontColor(Theme.text)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (row.running) {
                  Text('运行中')
                    .fontSize(Theme.fontSmall)
                    .fontColor(Theme.success)
                }
              }
              .width('100%')
              Row() {
                Text(row.cwd)
                  .fontSize(Theme.fontSmall)
                  .fontColor(Theme.textFaint)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(timeLabel(row.updatedAt))
                  .fontSize(Theme.fontSmall)
                  .fontColor(Theme.textFaint)
              }
              .width('100%')
              .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
          }
          .backgroundColor(Theme.card)
          .borderRadius(12)
          .margin({ left: Theme.pad, right: Theme.pad, top: 4, bottom: 4 })
          .onClick(() => {
            this.openSession(row.sessionId, row.title);
          })
        }, (row: SessionRow) => row.sessionId + ':' + row.updatedAt + ':' + row.running)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  chatView() {
    Column() {
      this.header(this.currentTitle, true)
      this.errorBar()

      List({ space: 2 }) {
        ForEach(this.items, (it: ChatItem) => {
          ListItem() {
            ChatRow({
              kind: it.kind,
              text: it.text,
              reasoning: it.reasoning,
              toolName: it.toolName,
              toolArgs: it.toolArgs,
              toolResult: it.toolResult,
              running: it.running,
              failed: it.failed,
              time: it.time
            })
          }
        }, (it: ChatItem) => it.key + '#' + it.text.length + '#' + it.reasoning.length + '#' +
        it.toolResult.length + '#' + (it.running ? '1' : '0'))
      }
      .layoutWeight(1)
      .width('100%')

      Row() {
        TextInput({ text: this.draft, placeholder: '说点什么…' })
          .layoutWeight(1)
          .fontSize(Theme.fontBody)
          .fontColor(Theme.text)
          .placeholderColor(Theme.textFaint)
          .backgroundColor(Theme.card)
          .borderRadius(12)
          .height(44)
          .onChange((v: string) => {
            this.draft = v;
          })
          .onSubmit(() => {
            this.send();
          })
        Button(this.busy ? '停止' : '发送')
          .height(44)
          .width(64)
          .margin({ left: 8 })
          .backgroundColor(this.busy ? Theme.danger : Theme.accent)
          .fontColor(this.busy ? '#1A0A0A' : '#06121E')
          .borderRadius(12)
          .onClick(() => {
            if (this.busy) {
              this.stopTurn();
            } else {
              this.send();
            }
          })
      }
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, top: 8, bottom: 14 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      if (this.stage === 'connect') {
        Scroll() {
          this.connectView()
        }
        .layoutWeight(1)
      } else if (this.stage === 'sessions') {
        Column() {
          this.sessionsView()
        }
        .layoutWeight(1)
      } else {
        Column() {
          this.chatView()
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
