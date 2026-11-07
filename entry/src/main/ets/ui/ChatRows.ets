/**
 * 聊天行组件：用户气泡 / 助手正文与思考 / 工具卡片 / 状态提示。
 *
 * 全部用 @Prop 基本类型传参，父组件替换数组即可触发刷新（鸿蒙 @Prop 的
 * 深拷贝语义对类实例不友好，这里避开）。
 */

import { Theme, timeLabel } from './Theme';

@Component
export struct ChatRow {
  @Prop kind: string = '';
  @Prop text: string = '';
  @Prop reasoning: string = '';
  @Prop toolName: string = '';
  @Prop toolArgs: string = '';
  @Prop toolResult: string = '';
  @Prop running: boolean = false;
  @Prop failed: boolean = false;
  @Prop time: number = 0;
  @State expandReasoning: boolean = false;
  @State expandTool: boolean = false;

  build() {
    Column() {
      if (this.kind === 'user') {
        Row() {
          Blank()
          Text(this.text)
            .fontSize(Theme.fontBody)
            .fontColor(Theme.text)
            .padding(12)
            .backgroundColor(Theme.accentSoft)
            .borderRadius(Theme.radius)
            .maxLines(200)
            .constraintSize({ maxWidth: '82%' })
        }
        .width('100%')
        .padding({ left: Theme.pad, right: Theme.pad, top: 6, bottom: 6 })
      } else if (this.kind === 'assistant') {
        Column() {
          if (this.reasoning.length > 0) {
            Column() {
              Row() {
                Text(this.expandReasoning ? '▾ 思考' : '▸ 思考')
                  .fontSize(Theme.fontSmall)
                  .fontColor(Theme.textFaint)
                Blank()
                Text(timeLabel(this.time))
                  .fontSize(Theme.fontSmall)
                  .fontColor(Theme.textFaint)
              }
              .width('100%')
              .onClick(() => {
                this.expandReasoning = !this.expandReasoning;
              })

              if (this.expandReasoning) {
                Text(this.reasoning)
                  .fontSize(Theme.fontSmall)
                  .fontColor(Theme.textFaint)
                  .width('100%')
                  .margin({ top: 6 })
                  .maxLines(400)
              }
            }
            .width('100%')
            .padding(10)
            .backgroundColor(Theme.cardAlt)
            .borderRadius(10)
            .margin({ bottom: 6 })
          }
          if (this.text.length > 0) {
            Text(this.text)
              .fontSize(Theme.fontBody)
              .fontColor(Theme.text)
              .width('100%')
              .maxLines(2000)
          }
          if (this.running) {
            Text('…')
              .fontSize(Theme.fontSmall)
              .fontColor(Theme.accent)
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Theme.pad, right: Theme.pad, top: 6, bottom: 6 })
      } else if (this.kind === 'tool') {
        Column() {
          Row() {
            Text(this.running ? '⚙ ' : (this.failed ? '✕ ' : '✓ '))
              .fontSize(Theme.fontSmall)
              .fontColor(this.running ? Theme.accent : (this.failed ? Theme.danger : Theme.success))
            Text(this.toolName)
              .fontSize(Theme.fontSmall)
              .fontColor(Theme.textDim)
              .layoutWeight(1)
            Text(this.expandTool ? '收起' : '详情')
              .fontSize(Theme.fontSmall)
              .fontColor(Theme.accent)
          }
          .width('100%')
          .onClick(() => {
            this.expandTool = !this.expandTool;
          })

          if (this.expandTool) {
            Text(this.toolArgs)
              .fontSize(Theme.monoSize)
              .fontColor(Theme.textDim)
              .width('100%')
              .margin({ top: 6 })
              .maxLines(40)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.toolResult.length > 0) {
              Divider().color(Theme.bgElevated).margin({ top: 6, bottom: 6 })
              Text(this.toolResult)
                .fontSize(Theme.monoSize)
                .fontColor(Theme.textDim)
                .width('100%')
                .maxLines(80)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .backgroundColor(Theme.card)
        .borderRadius(10)
        .margin({ left: Theme.pad, right: Theme.pad, top: 4, bottom: 4 })
      } else {
        Row() {
          Text(this.text)
            .fontSize(Theme.fontSmall)
            .fontColor(Theme.textFaint)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ left: Theme.pad, right: Theme.pad, top: 4, bottom: 4 })
      }
    }
    .width('100%')
  }
}
