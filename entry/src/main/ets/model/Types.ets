/**
 * DSH Go 鸿蒙端 —— 协议与领域模型。
 *
 * 全部类型对应 dsh-go 的 `packages/dsh_client`（Dart）中的定义：
 *   - 单次调用：POST /api/<endpoint>，信封见 RpcEnvelopeOut
 *   - 流式调用：WebSocket /api/remote.mux，帧见 MuxFrameIn / MuxFrameOut
 */

// ---------------------------------------------------------------------------
// JSON-RPC 信封（HTTP 单次调用）
// ---------------------------------------------------------------------------

export interface RpcPayloadOut {
  args: Object;
}

export interface RpcEnvelopeOut {
  type: string;      // 固定 'client-request'
  rpcId: string;     // 客户端生成的 uuid
  method: string;    // 'session/list' 等
  payload: RpcPayloadOut;
}

export interface RpcErrorInfo {
  code: string;
  message: string;
  details?: Object;
}

export interface RpcResultBody {
  ok: boolean;
  value?: Object;
  error?: RpcErrorInfo;
}

export interface RpcEnvelopeIn {
  type: string;      // 'server-response'
  rpcId: string;
  result?: RpcResultBody;
}

// ---------------------------------------------------------------------------
// Mux（WebSocket 多路流）
// ---------------------------------------------------------------------------

/** 空参数占位（ArkTS 不接受无类型对象字面量，必须给个具体类型）。 */
export interface EmptyArgs {
}

/** 逻辑流的打开参数：`{args: {...}}`。 */
export interface MuxPayload {
  args: Object;
}

export interface MuxFrameOut {
  type: string;      // 'open' | 'item' | 'end' | 'cancel'
  streamId: string;
  endpoint?: string; // open 时必填
  payload?: MuxPayload;  // open 时必填
  value?: Object;    // item 时必填
}

export interface MuxFrameIn {
  type: string;      // 'item' | 'end' | 'error'
  streamId: string;
  value?: Object;
  error?: RpcErrorInfo;
}

// ---------------------------------------------------------------------------
// 会话
// ---------------------------------------------------------------------------

export interface SessionHeaderRaw {
  version?: number;
  id: string;
  createdAt?: number;
  cwd?: string;
  agentPreset?: string;
  isSeeded?: boolean;
  delegationDepth?: number;
}

export interface ProjectionsRaw {
  asOfSeq?: number;
  kind?: string;
  values?: Object;
}

export interface SessionSummaryRaw {
  sessionId: string;
  updatedAt?: number;
  agentAvailable?: boolean;
  formatStatus?: string;
  running?: boolean;
  blank?: boolean;
  cwd?: string;
  title?: string;
  projections?: ProjectionsRaw;
}

export interface SessionListValue {
  items: SessionSummaryRaw[];
}

export interface SessionCreatedValue {
  sessionId: string;
  agentPreset?: string;
}

// ---------------------------------------------------------------------------
// 事件（durable log 与 assistant 流）
// ---------------------------------------------------------------------------

export interface ContentPartRaw {
  type: string;        // 'text' | 'reasoning' | 'tool-call' | 'image'
  text?: string;
  id?: string;
  name?: string;
  arguments?: string;
}

export interface MessageSourceRaw {
  kind?: string;       // 'user' | 'time-context' | 'tool' | ...
  callId?: string;
  form?: string;
}

export interface MessageRaw {
  role?: string;
  content?: ContentPartRaw[];
  source?: MessageSourceRaw;
  toolCallId?: string;
  isError?: boolean;
}

export interface TurnReasonRaw {
  kind?: string;       // 'interrupted' | 'completed' | 'error' ...
  message?: string;
}

export interface EventDataRaw {
  turn?: number;
  step?: number;
  message?: MessageRaw;
  content?: ContentPartRaw[];
  source?: MessageSourceRaw;
  callId?: string;
  name?: string;
  arguments?: string;
  toolCallId?: string;
  reason?: TurnReasonRaw;
  preset?: string;
  policy?: string;
}

export interface DshEventRaw {
  type: string;        // 'user/message' | 'assistant/message' | 'tool/call' ...
  seq: number;
  time: number;
  data?: EventDataRaw;
}

export interface RecordRaw {
  type: string;        // 'event'
  event: DshEventRaw;
}

export interface AssistantStreamRaw {
  revision?: number;
  text?: string;
}

export interface SnapshotRaw {
  type: string;        // 'snapshot'
  header?: SessionHeaderRaw;
  projections?: ProjectionsRaw;
  cursor?: number;
  records?: RecordRaw[];
  hasMore?: boolean;
  assistantStream?: AssistantStreamRaw;
}

export interface HistoryPageRaw {
  records?: RecordRaw[];
  hasMore?: boolean;
}

// ---------------------------------------------------------------------------
// 请求参数
// ---------------------------------------------------------------------------

export interface AddressRaw {
  kind: string;        // 'session'
  sessionId: string;
}

export interface EmptyRequest {
}

export interface EmptyRequestBody {
}

export interface SessionListArgs {
  _request: EmptyRequest;
}

export interface SessionCreateRequest {
  sessionId?: string;
  cwd?: string;
  workspaceId?: string;
  agentPreset?: string;
}

export interface SessionCreateArgs {
  request: SessionCreateRequest;
}

export interface PromptTextPart {
  type: string;        // 'text'
  text: string;
}

export interface PromptRequest {
  requestId: string;
  sessionId: string;
  mode: string;        // 'queue' | 'steer'
  content: PromptTextPart[];
  clientTimeZone?: string;
}

export interface PromptArgs {
  request: PromptRequest;
}

export interface SessionIdRequest {
  sessionId: string;
}

export interface SessionIdArgs {
  request: SessionIdRequest;
}

export interface TurnWindowRaw {
  minMessages: number;
  minTurns: number;
}

export interface FollowRequest {
  address: AddressRaw;
  assistantStream: boolean;
  maxMessages: number;
  turnWindow: TurnWindowRaw;
}

export interface FollowArgs {
  request: FollowRequest;
}

export interface HistoryRequest {
  address: AddressRaw;
  throughSeq: number;
  beforeSeq?: number;
  maxMessages?: number;
}

export interface HistoryArgs {
  request: HistoryRequest;
}

export interface RenameRequest {
  sessionId: string;
  title: string;
}

export interface RenameArgs {
  request: RenameRequest;
}

// ---------------------------------------------------------------------------
// UI 层用的聊天条目
// ---------------------------------------------------------------------------

export class ChatItem {
  key: string = '';
  kind: string = '';      // 'user' | 'assistant' | 'tool' | 'notice'
  text: string = '';
  reasoning: string = '';
  toolName: string = '';
  toolArgs: string = '';
  toolResult: string = '';
  callId: string = '';
  running: boolean = false;
  failed: boolean = false;
  time: number = 0;
  seq: number = 0;
}

export class SessionRow {
  sessionId: string = '';
  title: string = '';
  running: boolean = false;
  updatedAt: number = 0;
  cwd: string = '';
}
