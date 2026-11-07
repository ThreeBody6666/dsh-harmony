/**
 * 传输层：一个 `dsh web` 引擎的 HTTP 载体。
 *
 * 与 dsh_client 的 DshConnection 对齐：
 *   1. `GET /?token=<启动 token>` 换一个绑定 host:port 的会话 cookie（30 天有效）；
 *   2. 之后所有 `POST /api/<endpoint>` 带 `Cookie`，不带 `Origin`；
 *   3. 引擎的浏览器护栏只认 loopback 或 `--trusted-host` 的 Host，所以远程接入
 *      必须在电脑端用 `dsh web --host 0.0.0.0 --trusted-host <ip>:<port>` 启动。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  RpcEnvelopeOut,
  RpcEnvelopeIn,
  RpcPayloadOut,
  RpcResultBody
} from '../model/Types';

export class DshError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
    this.name = 'DshError';
  }
}

export class HttpReply {
  status: number = 0;
  body: string = '';
  cookies: string = '';
  setCookieHeader: string = '';
}

/** 极简 uuid v4，用于 rpcId / streamId。 */
export function uuidV4(): string {
  const hex: string[] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
  let out: string = '';
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      out += '-';
    } else if (i === 14) {
      out += '4';
    } else if (i === 19) {
      const r: number = Math.floor(Math.random() * 4);
      out += hex[8 + r];
    } else {
      out += hex[Math.floor(Math.random() * 16)];
    }
  }
  return out;
}

export class DshConnection {
  baseUrl: string = '';
  cookie: string = '';
  /** 引擎 authority，如 `127.0.0.1:3080`；cookie 与它绑定。 */
  authority: string = '';

  constructor(baseUrl: string) {
    let b: string = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    this.baseUrl = b;
    const stripped: string = b.replace('http://', '').replace('https://', '');
    const slash: number = stripped.indexOf('/');
    this.authority = slash >= 0 ? stripped.substring(0, slash) : stripped;
  }

  /** 单次 GET，只用于登录换 cookie 与健康检查。 */
  async get(path: string): Promise<HttpReply> {
    const client = http.createHttp();
    const reply = new HttpReply();
    const headers: Record<string, string> = {
      'Accept': 'text/html,application/json'
    };
    if (this.cookie.length > 0) {
      headers['Cookie'] = this.cookie;
    }
    try {
      const resp: http.HttpResponse = await client.request(this.baseUrl + path, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 20000
      });
      reply.status = resp.responseCode as number;
      reply.body = typeof resp.result === 'string' ? resp.result as string : '';
      reply.cookies = resp.cookies === undefined ? '' : resp.cookies;
      // HttpResponse.header 是 Object：set-cookie 可能以数组或字符串出现，
      // 不同版本行为不一致，这里统一取出来备用。
      const headerMap: Record<string, Object> = resp.header as Record<string, Object>;
      const sc: Object | undefined = headerMap['set-cookie'];
      if (sc !== undefined) {
        reply.setCookieHeader = sc as string;
      }
    } catch (e) {
      const err = e as BusinessError;
      throw new DshError('net/http', `连接失败：${err.message}（${err.code}）`);
    } finally {
      client.destroy();
    }
    return reply;
  }

  /**
   * 用启动 token 换 cookie。返回形如 `dsh-auth-xxx=v1.yyy.zzz` 的 Cookie 头值。
   * 引擎登录成功会 303 到 `/` 并 Set-Cookie；http 模块默认跟随重定向，
   * 所以最终响应里仍能取到 cookies。
   */
  async login(token: string): Promise<string> {
    const path: string = `/?token=${encodeURIComponent(token)}`;
    const reply: HttpReply = await this.get(path);
    let found: string = extractDshCookie(reply.cookies);
    if (found.length === 0) {
      found = extractDshCookie(reply.setCookieHeader);
    }
    if (found.length === 0) {
      found = extractDshCookie(reply.body);
    }
    if (found.length === 0) {
      if (reply.status === 401 || reply.status === 403) {
        throw new DshError('auth/denied', `登录被拒绝（HTTP ${reply.status}），token 可能已过期`);
      }
      throw new DshError(
        'auth/no-cookie',
        `登录未拿到 cookie（HTTP ${reply.status}）。请确认地址与 token 来自同一次 dsh web 启动输出。`
      );
    }
    this.cookie = found;
    return found;
  }

  /** 单次 RPC：POST /api/<endpoint>，返回 result（ok 为 false 时抛 DshError）。 */
  async rpc(endpoint: string, args: Object, readTimeoutMs: number = 120000): Promise<RpcResultBody> {
    const envelope: RpcEnvelopeOut = {
      type: 'client-request',
      rpcId: uuidV4(),
      method: endpoint,
      payload: { args: args } as RpcPayloadOut
    };
    const client = http.createHttp();
    let resp: http.HttpResponse;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'accept': 'application/json',
      'Cookie': this.cookie
    };
    try {
      resp = await client.request(`${this.baseUrl}/api/${endpoint}`, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(envelope),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: readTimeoutMs
      });
    } catch (e) {
      const err = e as BusinessError;
      throw new DshError('net/http', `${endpoint} 请求失败：${err.message}（${err.code}）`);
    } finally {
      client.destroy();
    }

    const status: number = resp.responseCode as number;
    const text: string = typeof resp.result === 'string' ? resp.result as string : '';
    if (status === 401 || status === 403) {
      throw new DshError('auth/expired', 'cookie 失效（HTTP ' + status + '），请重新登录');
    }
    if (status !== 200) {
      throw new DshError('http/' + status, `${endpoint} 返回 HTTP ${status}：${text.substring(0, 200)}`);
    }

    let parsed: RpcEnvelopeIn;
    try {
      parsed = JSON.parse(text) as RpcEnvelopeIn;
    } catch (e) {
      throw new DshError('protocol/bad-json', `${endpoint} 返回了无法解析的响应`);
    }
    const result: RpcResultBody | undefined = parsed.result;
    if (result === undefined) {
      throw new DshError('protocol/no-result', `${endpoint} 响应缺少 result`);
    }
    if (!result.ok) {
      const err = result.error;
      const code: string = err === undefined || err.code === undefined ? 'gateway/unknown' : err.code;
      const message: string = err === undefined || err.message === undefined ? '调用失败' : err.message;
      throw new DshError(code, `${endpoint}: ${message}`);
    }
    return result;
  }
}

/** 从 cookies / 响应文本里抠出 `dsh-auth-…=v1.…` 这一段。 */
export function extractDshCookie(text: string): string {
  if (text === undefined || text === null || text.length === 0) {
    return '';
  }
  const match: RegExpMatchArray | null = text.match(/dsh-auth-[A-Za-z0-9_-]+=v1\.[^\s;,]+/);
  if (match === null) {
    return '';
  }
  return match[0];
}
