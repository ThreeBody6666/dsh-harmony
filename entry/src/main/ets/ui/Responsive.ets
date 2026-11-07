/**
 * 断点系统：按窗口宽度（vp）划分，官方断点定义为
 *   xs (0, 320) / sm [320, 600) / md [600, 840) / lg [840, 1440) / xl [1440, +∞)
 *
 * MatePad 11.5S 2025（2800×1840，约 291ppi）折算下来：
 *   横屏约 1538vp → xl（两栏）
 *   竖屏约 1011vp → lg（两栏）
 * 所以平板上默认就是「左边会话列表 + 右边聊天」的双栏布局。
 */

export class Breakpoints {
  static readonly SM: string = 'sm';
  static readonly MD: string = 'md';
  static readonly LG: string = 'lg';
  static readonly XL: string = 'xl';

  static of(widthVp: number): string {
    if (widthVp >= 1440) {
      return Breakpoints.XL;
    }
    if (widthVp >= 840) {
      return Breakpoints.LG;
    }
    if (widthVp >= 600) {
      return Breakpoints.MD;
    }
    return Breakpoints.SM;
  }

  /** 是否用双栏（lg / xl）。 */
  static isWide(bp: string): boolean {
    return bp === Breakpoints.LG || bp === Breakpoints.XL;
  }

  /** 侧栏宽度：x l 稍宽一点。 */
  static sidebarWidth(bp: string): number {
    return bp === Breakpoints.XL ? 360 : 320;
  }

  /** 正文最大宽度，避免大屏上一行拉到天边。 */
  static contentMaxWidth(bp: string): number {
    return bp === Breakpoints.XL ? 900 : 760;
  }
}

/** 把 onAreaChange 给的 Length 安全转成 vp 数值。 */
export function lengthToVp(value: Length): number {
  if (typeof value === 'number') {
    const n: number = value as number;
    return n > 0 ? n : 0;
  }
  const text: string = value as string;
  const parsed: number = parseFloat(text);
  return isNaN(parsed) ? 0 : parsed;
}

export function isNaN(value: number): boolean {
  return value !== value;
}
