/**
 * 应用入口：初始化本地存储，加载主页面。
 */

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Store } from '../ui/Storage';

const TAG: string = 'DSHGo';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate');
    // 调试通道：用 `hdc shell aa start ... --ps autotest 1` 启动时自动跑自检，
    // `--ps autohost 1` 时自动启动本机引擎。没有人手点也能验证。
    AppStorage.setOrCreate('autoTest', String(want.parameters?.autotest ?? '') === '1');
    AppStorage.setOrCreate('autoHost', String(want.parameters?.autohost ?? '') === '1');
    Store.init(this.context).catch((e: BusinessError) => {
      hilog.warn(0x0000, TAG, 'preferences init failed: %{public}s', e.message);
    });
  }

  /**
   * 热启动（应用已在运行）时也要能接受命令行指令：
   *   hdc shell aa start -b com.dshgo.app -a EntryAbility --ps autohost 1
   * onCreate 只在冷启动走，所以这里必须再处理一次。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onNewWant');
    AppStorage.setOrCreate('autoTest', String(want.parameters?.autotest ?? '') === '1');
    AppStorage.setOrCreate('autoHost', String(want.parameters?.autohost ?? '') === '1');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code !== 0) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, TAG, 'content loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
