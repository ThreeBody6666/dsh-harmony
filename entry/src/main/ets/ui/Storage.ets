/**
 * 本地持久化：用 ArkData 的 preferences 保存「上次连接地址 / token / cookie」，
 * 以及会话草稿。
 *
 * 注意：cookie 是 bearer 凭据，正式发版应换到 @ohos.security.asset（系统密钥库）；
 * 这里先用 preferences 保证可跑通，文档里已标注为待办。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

const STORE_NAME: string = 'dshgo';

export class Store {
  private static store: preferences.Preferences | null = null;

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (Store.store !== null) {
      return;
    }
    const options: preferences.Options = { name: STORE_NAME };
    Store.store = await preferences.getPreferences(context, options);
  }

  static async get(key: string, defValue: string): Promise<string> {
    if (Store.store === null) {
      return defValue;
    }
    const value = Store.store.getSync(key, defValue);
    if (value === undefined || value === null) {
      return defValue;
    }
    return value as string;
  }

  static async put(key: string, value: string): Promise<void> {
    if (Store.store === null) {
      return;
    }
    Store.store.putSync(key, value);
    Store.store.flush().catch((e: BusinessError) => {
      // 持久化失败不阻塞交互
    });
  }

  static async remove(key: string): Promise<void> {
    if (Store.store === null) {
      return;
    }
    Store.store.deleteSync(key);
    Store.store.flush().catch((e: BusinessError) => {
    });
  }
}
