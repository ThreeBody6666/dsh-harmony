/**
 * 客户端门面：登录、会话列表、聊天流、发消息、中断。
 *
 * 对应 dsh_client 的 DshClient，只保留鸿蒙端 MVP 需要的那部分能力：
 *   session/list、session/create、session/page、session/prompt、session/cancel、
 *   以及 session/follow 的实时流（含断线重连与 snapshot 重同步）。
 */

import { DshConnection, DshError } from '../net/Connection';
import { DshMux, MuxListener } from '../net/Mux';
import { uuidV4 } from '../net/Connection';
import { Transcript } from './Transcript';
import {
  AddressRaw,
  DshEventRaw,
  EmptyRequest,
  EmptyRequestBody,
  FollowArgs,
  HistoryArgs,
  PromptArgs,
  PromptTextPart,
  RecordRaw,
  RpcErrorInfo,
  SessionCreateArgs,
  SessionCreatedValue,
  SessionIdArgs,
  SessionListArgs,
  SessionListValue,
  SessionRow,
  SessionSummaryRaw,
  SnapshotRaw
} from '../model/Types';

/** 会话列表里取标题：优先 projections.values.title。 */
function readSessionTitle(item: SessionSummaryRaw): string {
  if (item.title !== undefined && item.title !== null && item.title.length > 0) {
    return item.title;
  }
  const proj = item.projections;
  if (proj === undefined || proj.values === undefined || proj.values === null) {
    return '';
  }
  const values: Record<string, Object> = proj.values as Record<string, Object>;
  const t: Object | undefined = values['title'];
  if (t === undefined || t === null) {
    return '';
  }
  return t as string;
}

export class SessionWatch implements MuxListener {
  client: DshClient;
  sessionId: string = '';
  streamId: string = uuidV4();
  transcript: Transcript = new Transcript();
  onUpdate: () => void;
  onStatus: (text: string) => void;
  private mux: DshMux | null = null;
  private stopped: boolean = false;
  private retries: number = 0;
  private opened: boolean = false;

  constructor(client: DshClient, sessionId: string, onUpdate: () => void, onStatus: (text: string) => void) {
    this.client = client;
    this.sessionId = sessionId;
    this.onUpdate = onUpdate;
    this.onStatus = onStatus;
  }

  async start(): Promise<void> {
    this.stopped = false;
    this.transcript.reset();
    await this.connectOnce();
  }

  stop(): void {
    this.stopped = true;
    if (this.mux !== null) {
      const mux: DshMux = this.mux;
      this.mux = null;
      mux.cancel(this.streamId);
      mux.close();
    }
  }

  private async connectOnce(): Promise<void> {
    if (this.stopped) {
      return;
    }
    this.onStatus('连接中…');
    const mux: DshMux = new DshMux(this.client.muxUrl(), this);
    this.mux = mux;
    try {
      await mux.connect(this.client.conn.cookie);
    } catch (e) {
      this.onStatus('连接失败，重试中…');
      this.scheduleRetry();
      return;
    }
    if (this.stopped) {
      mux.close();
      return;
    }
    const args: FollowArgs = {
      request: {
        address: { kind: 'session', sessionId: this.sessionId } as AddressRaw,
        assistantStream: true,
        maxMessages: 500,
        turnWindow: { minMessages: 50, minTurns: 2 }
      }
    };
    this.streamId = uuidV4();
    mux.open(this.streamId, 'session/follow', args);
    this.onStatus('');
  }

  private scheduleRetry(): void {
    if (this.stopped) {
      return;
    }
    this.retries++;
    if (this.retries > 6) {
      this.onStatus('连接反复失败，请检查网络');
      return;
    }
    const delay: number = Math.min(500 * this.retries, 4000);
    setTimeout(() => {
      this.connectOnce();
    }, delay);
  }

  // --- MuxListener ---

  onReady(clientId: string): void {
    this.retries = 0;
    if (this.mux !== null && this.streamId.length > 0) {
      // ready 之后重新开 follow（世代变了，旧流已失效）
      const args: FollowArgs = {
        request: {
          address: { kind: 'session', sessionId: this.sessionId } as AddressRaw,
          assistantStream: true,
          maxMessages: 500,
          turnWindow: { minMessages: 50, minTurns: 2 }
        }
      };
      this.streamId = uuidV4();
      this.mux.open(this.streamId, 'session/follow', args);
    }
  }

  onItem(streamId: string, value: Object): void {
    if (streamId !== this.streamId) {
      return;
    }
    const map: Record<string, Object> = value as Record<string, Object>;
    const type: string = map['type'] === undefined ? '' : map['type'] as string;
    if (type === 'snapshot') {
      this.transcript.applySnapshot(value as SnapshotRaw);
      this.opened = true;
      this.onUpdate();
      this.onStatus('');
    } else if (type === 'event') {
      const ev: Object | undefined = map['event'];
      if (ev === undefined) {
        return;
      }
      this.transcript.applyEvent(ev as DshEventRaw);
      this.onUpdate();
    } else if (type === 'assistant-stream') {
      const frame: Object | undefined = map['frame'];
      if (frame !== undefined) {
        this.transcript.applyChunk(frame);
        this.onUpdate();
      }
    }
  }

  onEnd(streamId: string): void {
    if (streamId !== this.streamId) {
      return;
    }
    this.opened = false;
    this.scheduleRetry();
  }

  onError(streamId: string, error: RpcErrorInfo): void {
    if (streamId !== this.streamId) {
      return;
    }
    this.onStatus(`${error.code}: ${error.message}`);
  }

  onClosed(reason: string): void {
    if (this.stopped) {
      return;
    }
    this.onStatus(reason);
    this.scheduleRetry();
  }
}

export class DshClient {
  conn: DshConnection;
  title: string = '';

  constructor(conn: DshConnection) {
    this.conn = conn;
  }

  /** 换 cookie 并返回客户端实例。 */
  static async login(baseUrl: string, token: string): Promise<DshClient> {
    const conn = new DshConnection(baseUrl);
    await conn.login(token);
    return new DshClient(conn);
  }

  muxUrl(): string {
    const ws: string = this.conn.baseUrl.startsWith('https://')
      ? 'wss://' + this.conn.baseUrl.substring('https://'.length)
      : 'ws://' + this.conn.baseUrl.substring('http://'.length);
    return ws + '/api/remote.mux';
  }

  async listSessions(): Promise<SessionRow[]> {
    const emptyRequest: EmptyRequest = {};
    const args: SessionListArgs = { _request: emptyRequest };
    const result = await this.conn.rpc('session/list', args);
    const rawValue: Object | undefined = result.value;
    if (rawValue === undefined) {
      return [];
    }
    const value: SessionListValue = rawValue as SessionListValue;
    const items: SessionSummaryRaw[] = value.items === undefined ? [] : value.items;
    const rows: SessionRow[] = [];
    for (let i = 0; i < items.length; i++) {
      const raw: SessionSummaryRaw = items[i];
      if (raw.blank === true) {
        continue;
      }
      const row = new SessionRow();
      row.sessionId = raw.sessionId;
      row.title = readSessionTitle(raw);
      row.running = raw.running === true;
      row.updatedAt = raw.updatedAt === undefined ? 0 : raw.updatedAt;
      row.cwd = raw.cwd === undefined ? '' : raw.cwd;
      rows.push(row);
    }
    rows.sort((a: SessionRow, b: SessionRow) => b.updatedAt - a.updatedAt);
    return rows;
  }

  async createSession(): Promise<string> {
    const emptyBody: EmptyRequestBody = {};
    const args: SessionCreateArgs = { request: emptyBody };
    const result = await this.conn.rpc('session/create', args);
    const rawValue: Object | undefined = result.value;
    if (rawValue === undefined) {
      throw new DshError('session/create', '创建会话未返回 sessionId');
    }
    const value: SessionCreatedValue = rawValue as SessionCreatedValue;
    return value.sessionId;
  }

  async prompt(sessionId: string, text: string): Promise<string> {
    const requestId: string = uuidV4();
    const parts: PromptTextPart[] = [{ type: 'text', text: text }];
    const args: PromptArgs = {
      request: {
        requestId: requestId,
        sessionId: sessionId,
        mode: 'queue',
        content: parts
      }
    };
    await this.conn.rpc('session/prompt', args);
    return requestId;
  }

  async cancel(sessionId: string): Promise<void> {
    const args: SessionIdArgs = { request: { sessionId: sessionId } };
    await this.conn.rpc('session/cancel', args);
  }

  /** 读一页更早的历史（向上翻页用）。 */
  async history(sessionId: string, throughSeq: number, beforeSeq: number): Promise<RecordRaw[]> {
    const args: HistoryArgs = {
      request: {
        address: { kind: 'session', sessionId: sessionId } as AddressRaw,
        throughSeq: throughSeq,
        beforeSeq: beforeSeq,
        maxMessages: 200
      }
    };
    const result = await this.conn.rpc('session/page', args);
    const rawValue: Object | undefined = result.value;
    if (rawValue === undefined) {
      return [];
    }
    const map: Record<string, Object> = rawValue as Record<string, Object>;
    const records: Object | undefined = map['records'];
    if (records === undefined) {
      return [];
    }
    return records as Object as RecordRaw[];
  }

  watch(sessionId: string, onUpdate: () => void, onStatus: (text: string) => void): SessionWatch {
    return new SessionWatch(this, sessionId, onUpdate, onStatus);
  }
}
