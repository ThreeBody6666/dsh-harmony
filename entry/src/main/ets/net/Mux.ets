/**
 * 传输层：`/api/remote.mux` 的 WebSocket 多路复用。
 *
 * 一帧一条 JSON 文本消息：
 *   client -> host  {type:'open', streamId, endpoint, payload:{args:{...}}}
 *                   {type:'item', streamId, value}
 *                   {type:'end', streamId}
 *                   {type:'cancel', streamId}
 *   host -> client  {type:'item', streamId, value}
 *                   {type:'end', streamId}
 *                   {type:'error', streamId, error:{code,message}}
 *
 * 每个连接世代先开一条 `$events` 流，首帧必须是 `{type:'ready', clientId}`；
 * 拿到 ready 之后才能开别的流（与 Dart 侧 Mux.ready 的约定一致）。
 */

import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { MuxFrameIn, RpcErrorInfo } from '../model/Types';

export interface MuxListener {
  onReady: (clientId: string) => void;
  onItem: (streamId: string, value: Object) => void;
  onEnd: (streamId: string) => void;
  onError: (streamId: string, error: RpcErrorInfo) => void;
  onClosed: (reason: string) => void;
}

const EVENTS_STREAM: string = 'mux-events';

export class DshMux {
  private ws: webSocket.WebSocket | null = null;
  private listener: MuxListener | null = null;
  private ready: boolean = false;
  private closed: boolean = false;
  private clientId: string = '';
  url: string = '';

  constructor(url: string, listener: MuxListener) {
    this.url = url;
    this.listener = listener;
  }

  isReady(): boolean {
    return this.ready;
  }

  getClientId(): string {
    return this.clientId;
  }

  connect(cookie: string): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (e: Error) => void) => {
      const ws: webSocket.WebSocket = webSocket.createWebSocket();
      this.ws = ws;
      let settled: boolean = false;

      ws.on('open', (err: BusinessError, value: Object) => {
        // 世代建立：先开 $events，等 ready
        this.sendRaw({
          type: 'open',
          streamId: EVENTS_STREAM,
          endpoint: '$events',
          payload: { args: {} }
        });
      });

      ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
        if (typeof value !== 'string') {
          this.fail('二进制帧不受支持');
          return;
        }
        this.handleFrame(value as string);
        if (!settled && this.ready) {
          settled = true;
          resolve();
        }
      });

      ws.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
        this.closed = true;
        this.ready = false;
        if (this.listener !== null) {
          this.listener.onClosed('连接已断开');
        }
        if (!settled) {
          settled = true;
          reject(new Error('WebSocket 在 ready 之前断开'));
        }
      });

      ws.on('error', (err: BusinessError) => {
        this.closed = true;
        this.ready = false;
        if (!settled) {
          settled = true;
          reject(new Error(`WebSocket 错误：${err.message}（${err.code}）`));
        }
        if (this.listener !== null) {
          this.listener.onClosed(`WebSocket 错误：${err.message}`);
        }
      });

      const headers: Record<string, string> = {
        'Cookie': cookie
      };
      ws.connect(this.url, { header: headers }).catch((e: BusinessError) => {
        if (!settled) {
          settled = true;
          reject(new Error(`连接 ${this.url} 失败：${e.message}`));
        }
      });
    });
  }

  private fail(reason: string): void {
    this.closed = true;
    if (this.listener !== null) {
      this.listener.onClosed(reason);
    }
  }

  private handleFrame(text: string): void {
    let frame: MuxFrameIn;
    try {
      frame = JSON.parse(text) as MuxFrameIn;
    } catch (e) {
      this.fail('收到无法解析的帧');
      return;
    }
    if (frame.streamId === undefined || frame.type === undefined) {
      this.fail('帧缺少 streamId/type');
      return;
    }
    if (frame.streamId === EVENTS_STREAM) {
      if (frame.type === 'item' && frame.value !== undefined) {
        const value = frame.value as Record<string, Object>;
        const kind: string = value['type'] === undefined ? '' : value['type'] as string;
        if (kind === 'ready') {
          this.ready = true;
          const cid: Object | undefined = value['clientId'];
          this.clientId = cid === undefined ? '' : cid as string;
          if (this.listener !== null) {
            this.listener.onReady(this.clientId);
          }
        }
      }
      return;
    }
    if (frame.type === 'item' && frame.value !== undefined) {
      if (this.listener !== null) {
        this.listener.onItem(frame.streamId, frame.value);
      }
    } else if (frame.type === 'end') {
      if (this.listener !== null) {
        this.listener.onEnd(frame.streamId);
      }
    } else if (frame.type === 'error') {
      const error: RpcErrorInfo = frame.error === undefined
        ? { code: 'mux/error', message: '流错误' }
        : frame.error;
      if (this.listener !== null) {
        this.listener.onError(frame.streamId, error);
      }
    }
  }

  private sendRaw(frame: Object): void {
    if (this.ws === null || this.closed) {
      return;
    }
    this.ws.send(JSON.stringify(frame)).catch((e: BusinessError) => {
      this.fail(`发送失败：${e.message}`);
    });
  }

  /** 开一条逻辑流；payload 必须是 `{args: {...}}`。 */
  open(streamId: string, endpoint: string, args: Object): void {
    this.sendRaw({
      type: 'open',
      streamId: streamId,
      endpoint: endpoint,
      payload: { args: args }
    });
  }

  cancel(streamId: string): void {
    this.sendRaw({
      type: 'cancel',
      streamId: streamId
    });
  }

  close(): void {
    this.closed = true;
    this.ready = false;
    if (this.ws === null) {
      return;
    }
    const ws: webSocket.WebSocket = this.ws;
    this.ws = null;
    ws.close().catch((e: BusinessError) => {
      // 关闭失败无需上报
    });
  }
}
