/**
 * 设计令牌：跟随 dsh-go 的深色玻璃质感，但只用 ArkUI 原生能力实现。
 */

export class Theme {
  // 背景（由深到浅）
  static readonly bg: string = '#08131F';
  static readonly bgElevated: string = '#0F2133';
  static readonly card: string = '#16293D';
  static readonly cardAlt: string = '#1B3147';

  // 文字
  static readonly text: string = '#E7F0F8';
  static readonly textDim: string = '#9DB2C7';
  static readonly textFaint: string = '#6B8299';

  // 强调
  static readonly accent: string = '#3BA8FF';
  static readonly accentSoft: string = '#1D5C8C';
  static readonly danger: string = '#FF6B6B';
  static readonly success: string = '#4ECB8F';

  // 尺寸
  static readonly radius: number = 14;
  static readonly gap: number = 10;
  static readonly pad: number = 14;
  static readonly fontBody: number = 15;
  static readonly fontSmall: number = 12;
  static readonly fontTitle: number = 18;
  static readonly monoSize: number = 12;
}

export function timeLabel(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  const d = new Date(ms);
  const now = new Date();
  const hh: string = d.getHours() < 10 ? '0' + d.getHours() : '' + d.getHours();
  const mm: string = d.getMinutes() < 10 ? '0' + d.getMinutes() : '' + d.getMinutes();
  if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()) {
    return hh + ':' + mm;
  }
  const mo: string = d.getMonth() + 1 < 10 ? '0' + (d.getMonth() + 1) : '' + (d.getMonth() + 1);
  const dd: string = d.getDate() < 10 ? '0' + d.getDate() : '' + d.getDate();
  return mo + '-' + dd + ' ' + hh + ':' + mm;
}
