/**
 * DSH Go 鸿蒙端主页面（手机 / 平板自适应）。
 *
 * 布局按窗口宽度断点切换（见 ui/Responsive.ets）：
 *   sm / md  —— 单栏：连接 → 会话列表 → 聊天，逐级进入
 *   lg / xl  —— 双栏：左侧会话列表常驻，右侧聊天（MatePad 默认这种）
 */

import { ChatRow } from '../ui/ChatRows';
import { Theme, timeLabel } from '../ui/Theme';
import { Store } from '../ui/Storage';
import { Breakpoints, lengthToVp } from '../ui/Responsive';
import { DshClient, SessionWatch } from '../client/DshClient';
import { LocalEngine, LocalEngineError, LocalEngineInfo } from '../client/LocalEngine';
import { ChatItem, SessionRow } from '../model/Types';
import { DshError } from '../net/Connection';
import { common } from '@kit.AbilityKit';

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
  // 断点：由根容器实际宽度算出，旋转/分屏都会跟着变
  @State widthVp: number = 0;
  @State diagText: string = '';
  @State bp: string = Breakpoints.SM;

  private client: DshClient | null = null;
  private watch: SessionWatch | null = null;
  private localEngine: LocalEngine | null = null;

  aboutToAppear(): void {
    this.restore();
  }

  /** 开机自启本机引擎；失败才回落到手填地址的连接页。 */
  private async bootLocal(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.status = '启动本机引擎…';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const engine = new LocalEngine(context);
      this.localEngine = engine;
      const info: LocalEngineInfo = await engine.start();
      this.status = '登录本机引擎…';
      await this.connectWith(info.baseUrl, info.token);
    } catch (e) {
      // 没有核心树/宿主未接入时，安静回落到连接页
      const err = e as Error;
      this.errorText = err.message;
    } finally {
      this.busy = false;
      this.status = '';
    }
  }

  aboutToDisappear(): void {
    this.detach();
    this.stopLocalEngine();
  }

  private isWide(): boolean {
    return Breakpoints.isWide(this.bp);
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

  private stopLocalEngine(): void {
    if (this.localEngine !== null) {
      const engine: LocalEngine = this.localEngine;
      this.localEngine = null;
      engine.stop();
    }
  }

  // -------------------------------------------------------------------------
  // 流程
  // -------------------------------------------------------------------------

  /** 手填地址登录。 */
  private async connect(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    this.status = '正在登录…';
    try {
      await this.connectWith(this.baseUrl, this.token);
    } catch (e) {
      this.reportError(e);
    } finally {
      this.busy = false;
      this.status = '';
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
    // 双栏时：没有选中会话也进主界面，右侧显示占位
    if (this.isWide() && this.sessions.length > 0) {
      this.stage = 'chat';
    }
  }

  /** 本机模式：手机里起 VM，拿到 127.0.0.1 的引擎后走同一条登录链路。 */
  private async startLocal(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    this.status = '检查本机资源…';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const engine = new LocalEngine(context, (text: string) => {
        this.status = text;
      });
      this.localEngine = engine;
      const info: LocalEngineInfo = await engine.start();
      this.status = '登录本机引擎…';
      await this.connectWith(info.baseUrl, info.token);
    } catch (e) {
      this.reportError(e);
      if (this.localEngine !== null) {
        this.diagText = this.localEngine.readDiagnostics();
      }
    } finally {
      this.busy = false;
      this.status = '';
    }
  }

  private reportError(e: Object): void {
    if (e instanceof LocalEngineError) {
      const err = e as LocalEngineError;
      this.errorText = err.code + '：' + err.message;
    } else if (e instanceof DshError) {
      const err2 = e as DshError;
      this.errorText = err2.code + '：' + err2.message;
    } else {
      const err3 = e as Error;
      this.errorText = err3.message;
    }
  }

  private async refreshSessions(): Promise<void> {
    if (this.client === null) {
      return;
    }
    try {
      this.sessions = await this.client.listSessions();
    } catch (e) {
      this.reportError(e);
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
      this.reportError(e);
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
      this.reportError(e);
    }
  }

  private async stopTurn(): Promise<void> {
    if (this.client === null || this.currentId.length === 0) {
      return;
    }
    try {
      await this.client.cancel(this.currentId);
    } catch (e) {
      this.reportError(e);
    }
  }

  private backToSessions(): void {
    this.detach();
    this.currentId = '';
    this.stage = 'sessions';
    this.refreshSessions();
  }

  // -------------------------------------------------------------------------
  // 组件
  // -------------------------------------------------------------------------

  @Builder
  header(title: string, back: boolean) {
    Row() {
      if (back) {
        Text('‹')
          .fontSize(26)
          .fontColor(Theme.text)
          .width(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.backToSessions();
          })
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
          .margin({ right: 8 })
      }
      Text('设')
        .fontSize(Theme.fontSmall)
        .fontColor(Theme.textDim)
        .padding(8)
        .onClick(() => {
          this.showEngineInfo();
        })
    }
    .width('100%')
    .height(this.isWide() ? 60 : 52)
    .padding({ left: 8, right: Theme.pad })
  }

  private showEngineInfo(): void {
    this.errorText = `布局：${this.bp}（${Math.round(this.widthVp)}vp）` +
      `　会话：${this.currentId.length > 0 ? '已选' : '未选'}　` +
      (this.client === null ? '未连接引擎' : '已连接引擎');
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
        .fontSize(this.isWide() ? 34 : 30)
        .fontColor(Theme.text)
        .fontWeight(FontWeight.Medium)
        .margin({ top: this.isWide() ? 60 : 70, bottom: 6 })
      Text('鸿蒙客户端 · 平板适配版')
        .fontSize(Theme.fontSmall)
        .fontColor(Theme.textDim)
        .margin({ bottom: 26 })

      this.errorBar()
      if (this.diagText.length > 0) {
        Text(this.diagText)
          .fontSize(10)
          .fontColor(Theme.textFaint)
          .width('100%')
          .margin({ bottom: 10 })
          .maxLines(10)
          .padding(8)
          .backgroundColor(Theme.bgElevated)
          .borderRadius(8)
      }

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
          .height(48)
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
          .height(48)
          .onChange((v: string) => {
            this.token = v;
          })

        Button(this.busy ? '登录中…' : '连接')
          .width('100%')
          .height(48)
          .margin({ top: 22 })
          .backgroundColor(Theme.accent)
          .fontColor('#06121E')
          .borderRadius(12)
          .enabled(!this.busy)
          .onClick(() => {
            this.connect();
          })

        Button(this.busy ? (this.status.length > 0 ? this.status : '启动中…') : '启动本机引擎（Node 内置）')
          .width('100%')
          .height(44)
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
        Text('本机模式 = 设备里跑一台 Linux 虚拟机，VM 内启动 dsh web；\n需先把 kernel/镜像打进包里（见 docs/LOCAL-ENGINE.md）。')
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.textFaint)
          .width('100%')
          .margin({ bottom: 10 })
        Text('连电脑的话，电脑端这样启动：')
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.textDim)
          .width('100%')
        Text('dsh web --host 0.0.0.0 --trusted-host <IP>:3080')
          .fontSize(Theme.monoSize)
          .fontColor(Theme.accent)
          .width('100%')
          .margin({ top: 6 })
      }
      .width('100%')
      .padding(12)
      .backgroundColor(Theme.bgElevated)
      .borderRadius(10)
      .margin({ top: 24 })
    }
    .width('100%')
    .constraintSize({ maxWidth: this.isWide() ? 560 : 100000 })
    .padding({ left: 18, right: 18 })
  }

  @Builder
  sessionRow(row: SessionRow) {
    Column() {
      Row() {
        Text(row.title.length > 0 ? row.title : row.sessionId.substring(0, 8))
          .fontSize(Theme.fontBody)
          .fontColor(row.sessionId === this.currentId ? Theme.accent : Theme.text)
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
    .backgroundColor(row.sessionId === this.currentId ? Theme.cardAlt : Theme.card)
    .borderRadius(12)
    .margin({ left: Theme.pad, right: Theme.pad, top: 4, bottom: 4 })
    .onClick(() => {
      this.openSession(row.sessionId, row.title);
    })
  }

  /** 会话面板：双栏时是常驻侧栏，单栏时是整页。 */
  @Builder
  sessionsPane(wide: boolean) {
    Column() {
      if (!wide) {
        this.header('会话', false)
      } else {
        Row() {
          Text('会话')
            .fontSize(Theme.fontTitle)
            .fontColor(Theme.text)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
        }
        .width('100%')
        .height(60)
        .padding({ left: Theme.pad, right: Theme.pad })
      }

      Row() {
        Button('新建')
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
            this.sessionRow(row)
          }
        }, (row: SessionRow) => row.sessionId + ':' + row.updatedAt + ':' + row.running + ':' +
        (row.sessionId === this.currentId ? '1' : '0'))
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }

  @Builder
  emptyChatPane() {
    Column() {
      Text('选一个会话开始')
        .fontSize(Theme.fontBody)
        .fontColor(Theme.textDim)
      Text('左上角可以新建会话')
        .fontSize(Theme.fontSmall)
        .fontColor(Theme.textFaint)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  messageList() {
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
    .constraintSize({ maxWidth: Breakpoints.contentMaxWidth(this.bp) })
  }

  @Builder
  composer() {
    Row() {
      TextInput({ text: this.draft, placeholder: '说点什么…' })
        .layoutWeight(1)
        .fontSize(Theme.fontBody)
        .fontColor(Theme.text)
        .placeholderColor(Theme.textFaint)
        .backgroundColor(Theme.card)
        .borderRadius(12)
        .height(this.isWide() ? 48 : 44)
        .onChange((v: string) => {
          this.draft = v;
        })
        .onSubmit(() => {
          this.send();
        })
      Button(this.busy ? '停止' : '发送')
        .height(this.isWide() ? 48 : 44)
        .width(this.isWide() ? 88 : 64)
        .margin({ left: 10 })
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
    .constraintSize({ maxWidth: Breakpoints.contentMaxWidth(this.bp) })
    .padding({ top: 8, bottom: this.isWide() ? 20 : 14 })
  }

  @Builder
  chatView() {
    Column() {
      if (!this.isWide()) {
        this.header(this.currentTitle, true)
      } else {
        Row() {
          Text(this.currentTitle)
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
          }
        }
        .width('100%')
        .height(60)
        .padding({ left: Theme.pad, right: Theme.pad })
      }
      this.errorBar()
      if (this.diagText.length > 0) {
        Text(this.diagText)
          .fontSize(10)
          .fontColor(Theme.textFaint)
          .width('100%')
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: Theme.pad, right: Theme.pad, bottom: 6 })
          .onClick(() => {
            this.diagText = '';
          })
      }
      this.messageList()
      this.composer()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  wideLayout() {
    Row() {
      Column() {
        this.sessionsPane(true)
      }
      .width(Breakpoints.sidebarWidth(this.bp))
      .height('100%')

      Divider()
        .vertical(true)
        .color(Theme.bgElevated)
        .strokeWidth(1)

      Column() {
        if (this.currentId.length > 0) {
          this.chatView()
        } else {
          this.emptyChatPane()
        }
      }
      .layoutWeight(1)
      .height('100%')
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
        .width('100%')
      } else if (this.isWide()) {
        this.wideLayout()
      } else if (this.stage === 'sessions') {
        this.sessionsPane(false)
      } else {
        this.chatView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const w: number = lengthToVp(newValue.width);
      if (w > 0 && Math.abs(w - this.widthVp) > 0.5) {
        this.widthVp = w;
        this.bp = Breakpoints.of(w);
      }
    })
  }
}
