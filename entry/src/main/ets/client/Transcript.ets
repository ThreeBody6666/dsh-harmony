/**
 * 把引擎事件折成可渲染的聊天条目。
 *
 * 输入：follow 流的三种帧
 *   {type:'snapshot'}        —— 首帧，带 records / cursor
 *   {type:'event', event}    —— 持久日志事件（user/message、assistant/message、tool/* …）
 *   {type:'assistant-stream', frame} —— 增量流（text-delta / reasoning-delta …）
 *
 * 与 dsh-go 的 ChatTranscript 相比，这里是 MVP 版本：只保留消息、思考、工具三
 * 类条目，注入型上下文（time-context、skill-catalog 等）默认不显示。
 */

import {
  ChatItem,
  DshEventRaw,
  EventDataRaw,
  ContentPartRaw,
  MessageRaw,
  RecordRaw,
  SnapshotRaw
} from '../model/Types';

const EMPTY_EVENT_DATA: EventDataRaw = {};

export class Transcript {
  items: ChatItem[] = [];
  cursor: number = -1;
  title: string = '';
  running: boolean = false;
  /** 还没拿到 snapshot 时收到的实时条目，等 snapshot 到达后清掉。 */
  private live: Map<string, ChatItem> = new Map<string, ChatItem>();
  private tools: Map<string, ChatItem> = new Map<string, ChatItem>();
  private dirty: boolean = false;

  reset(): void {
    this.items = [];
    this.cursor = -1;
    this.running = false;
    this.live.clear();
    this.tools.clear();
    this.dirty = false;
  }

  takeDirty(): boolean {
    const was: boolean = this.dirty;
    this.dirty = false;
    return was;
  }

  /** 应用 snapshot 帧：整段替换历史。 */
  applySnapshot(snap: SnapshotRaw): void {
    const next: ChatItem[] = [];
    this.live.clear();
    this.tools.clear();
    const records: RecordRaw[] = snap.records === undefined ? [] : snap.records;
    for (let i = 0; i < records.length; i++) {
      this.foldEvent(records[i].event, next);
    }
    this.items = next;
    this.cursor = snap.cursor === undefined ? -1 : snap.cursor;
    this.title = readTitle(snap);
    this.running = snap.assistantStream !== undefined;
    this.dirty = true;
  }

  /** 应用一条持久事件帧。 */
  applyEvent(event: DshEventRaw): void {
    if (event.seq <= this.cursor) {
      return;
    }
    if (event.seq > this.cursor + 1 && this.cursor >= 0) {
      // 有缺口：交给上层重连 + 重新 snapshot 修复
      this.cursor = event.seq - 1;
    }
    const next: ChatItem[] = this.items.slice();
    this.foldEvent(event, next);
    this.items = next;
    this.cursor = event.seq;
    this.dirty = true;
  }

  /** 应用 assistant-stream 增量帧。 */
  applyChunk(frame: Object): void {
    const map: Record<string, Object> = frame as Record<string, Object>;
    const kind: string = map['type'] === undefined ? '' : map['type'] as string;
    const chunkObj: Object | undefined = map['chunk'];
    if (chunkObj === undefined) {
      return;
    }
    const chunk: Record<string, Object> = chunkObj as Record<string, Object>;
    const chunkType: string = chunk['type'] === undefined ? '' : chunk['type'] as string;
    const text: string = chunk['text'] === undefined ? '' : chunk['text'] as string;
    if (text.length === 0) {
      return;
    }
    const next: ChatItem[] = this.items.slice();
    if (kind === 'start') {
      const item = new ChatItem();
      item.key = 'live-' + (map['attemptId'] === undefined ? 'x' : map['attemptId'] as string);
      item.kind = 'assistant';
      item.running = true;
      item.time = Date.now();
      next.push(item);
      this.live.set(item.key, item);
      this.items = next;
      this.running = true;
      this.dirty = true;
      return;
    }
    if (kind === 'end') {
      this.live.forEach((item: ChatItem, key: string) => {
        item.running = false;
      });
      this.running = false;
      this.items = next;
      this.dirty = true;
      return;
    }
    if (kind !== 'chunk') {
      return;
    }
    // 找当前未完成的实时条目
    let target: ChatItem | null = null;
    for (let i = next.length - 1; i >= 0; i--) {
      if (next[i].kind === 'assistant' && next[i].running) {
        target = next[i];
        break;
      }
    }
    if (target === null) {
      target = new ChatItem();
      target.key = 'live-' + Date.now();
      target.kind = 'assistant';
      target.running = true;
      target.time = Date.now();
      next.push(target);
    }
    if (chunkType === 'text-delta') {
      target.text = target.text + text;
    } else if (chunkType === 'reasoning-delta') {
      target.reasoning = target.reasoning + text;
    }
    this.items = next;
    this.running = true;
    this.dirty = true;
  }

  /** 丢掉还没落地的实时增量条目（它们已由 durable 事件接管）。 */
  private dropLive(out: ChatItem[]): void {
    for (let i = out.length - 1; i >= 0; i--) {
      if (out[i].key.startsWith('live-')) {
        out.splice(i, 1);
      }
    }
    this.live.clear();
  }

  /** 一条持久事件 -> 若干条目。 */
  private foldEvent(event: DshEventRaw, out: ChatItem[]): void {
    const data: EventDataRaw = event.data === undefined ? EMPTY_EVENT_DATA : event.data;
    switch (event.type) {
      case 'user/message': {
        const source = data.source;
        const kind: string = source === undefined || source.kind === undefined ? 'user' : source.kind;
        if (kind !== 'user' && kind !== 'rpc') {
          return; // 注入型上下文不显示
        }
        const text: string = contentText(data.content);
        if (text.trim().length === 0) {
          return;
        }
        const item = new ChatItem();
        item.key = 'u' + event.seq;
        item.kind = 'user';
        item.text = text;
        item.time = event.time;
        item.seq = event.seq;
        out.push(item);
        return;
      }
      case 'assistant/message': {
        // 持久事件落地：先清掉这一轮的实时增量条目，避免同一条出现两次
        this.dropLive(out);
        const msg: MessageRaw | undefined = data.message;
        if (msg === undefined) {
          return;
        }
        const parts: ContentPartRaw[] = msg.content === undefined ? [] : msg.content;
        let text: string = '';
        let reasoning: string = '';
        for (let i = 0; i < parts.length; i++) {
          const part: ContentPartRaw = parts[i];
          if (part.type === 'text' && part.text !== undefined) {
            text += part.text;
          } else if (part.type === 'reasoning' && part.text !== undefined) {
            reasoning += part.text;
          }
        }
        if (text.trim().length === 0 && reasoning.trim().length === 0) {
          return; // 只有工具调用：由 tool/call 事件负责渲染
        }
        const item = new ChatItem();
        item.key = 'a' + event.seq;
        item.kind = 'assistant';
        item.text = text;
        item.reasoning = reasoning;
        item.time = event.time;
        item.seq = event.seq;
        out.push(item);
        return;
      }
      case 'tool/call': {
        const item = new ChatItem();
        item.key = 't' + (data.callId === undefined ? event.seq.toString() : data.callId);
        item.kind = 'tool';
        item.callId = data.callId === undefined ? '' : data.callId;
        item.toolName = data.name === undefined ? 'tool' : data.name;
        item.toolArgs = data.arguments === undefined ? '' : data.arguments;
        item.running = true;
        item.time = event.time;
        item.seq = event.seq;
        out.push(item);
        if (item.callId.length > 0) {
          this.tools.set(item.callId, item);
        }
        return;
      }
      case 'tool/result': {
        // toolCallId 在 message 里（message.toolCallId），不在 data 上
        const msg: MessageRaw | undefined = data.message;
        let callId: string = data.toolCallId === undefined ? '' : data.toolCallId;
        if (callId.length === 0 && msg !== undefined) {
          if (msg.toolCallId !== undefined) {
            callId = msg.toolCallId;
          } else if (msg.source !== undefined && msg.source.callId !== undefined) {
            callId = msg.source.callId;
          }
        }
        const resultText: string = msg === undefined ? contentText(data.content) : contentText(msg.content);
        const target: ChatItem | undefined = this.tools.get(callId);
        if (target !== undefined) {
          target.toolResult = resultText;
          target.running = false;
          target.failed = msg !== undefined && msg.isError === true;
          return;
        }
        return;
      }
      case 'turn/end': {
        this.dropLive(out);
        this.running = false;
        const reason = data.reason;
        const kind: string = reason === undefined || reason.kind === undefined ? '' : reason.kind;
        if (kind === 'interrupted') {
          out.push(notice('t' + event.seq, '已中断', event.time));
        } else if (kind === 'error') {
          const text: string = reason !== undefined && reason.message !== undefined ? reason.message : '出错了';
          out.push(notice('t' + event.seq, text, event.time));
        }
        return;
      }
      case 'turn/start': {
        this.running = true;
        return;
      }
      default:
        return;
    }
  }
}

function notice(key: string, text: string, time: number): ChatItem {
  const item = new ChatItem();
  item.key = key;
  item.kind = 'notice';
  item.text = text;
  item.time = time;
  return item;
}

function contentText(parts: ContentPartRaw[] | undefined): string {
  if (parts === undefined) {
    return '';
  }
  let out: string = '';
  for (let i = 0; i < parts.length; i++) {
    const part: ContentPartRaw = parts[i];
    if (part.type === 'text' && part.text !== undefined) {
      out += part.text;
    }
  }
  return out;
}

function readTitle(snap: SnapshotRaw): string {
  const proj = snap.projections;
  if (proj === undefined || proj.values === undefined) {
    return '';
  }
  const values: Record<string, Object> = proj.values as Record<string, Object>;
  const title: Object | undefined = values['title'];
  if (title === undefined) {
    return '';
  }
  return title as string;
}
