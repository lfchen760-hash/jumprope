/**
 * 姿态判定 —— 浏览器与离线回放共用。
 */

/* ---- 姿态判定：站直 / 弯腰 / 蹲坐 / 躺卧 ---- */
export function angleAt(a, b, c) {
  // 返回以 b 为顶点的夹角（度）
  const v1x = a.x - b.x, v1y = a.y - b.y;
  const v2x = c.x - b.x, v2y = c.y - b.y;
  const m1 = Math.hypot(v1x, v1y);
  const m2 = Math.hypot(v2x, v2y);
  if (m1 < 1e-6 || m2 < 1e-6) return 180;
  let cos = (v1x * v2x + v1y * v2y) / (m1 * m2);
  cos = Math.max(-1, Math.min(1, cos));
  return (Math.acos(cos) * 180) / Math.PI;
}

export function postureOf(lm) {
  const vis = (i) => (lm[i] && lm[i].visibility != null ? lm[i].visibility : 1);

  const shMid = { x: (lm[11].x + lm[12].x) / 2, y: (lm[11].y + lm[12].y) / 2 };
  const hipMid = { x: (lm[23].x + lm[24].x) / 2, y: (lm[23].y + lm[24].y) / 2 };

  // 躯干相对竖直方向的倾角：站立≈0°，躺下≈90°
  const dx = shMid.x - hipMid.x;
  const dy = shMid.y - hipMid.y;
  const tilt = Math.abs((Math.atan2(dx, -dy) * 180) / Math.PI);

  // 膝关节角度：伸直≈180°，下蹲≈90°
  const kneeL = angleAt(lm[23], lm[25], lm[27]);
  const kneeR = angleAt(lm[24], lm[26], lm[28]);
  const knee = Math.max(kneeL, kneeR);

  // 全身是否入镜：鼻子 + 两只脚踝
  const fullBody =
    vis(0) > 0.4 && vis(27) > 0.4 && vis(28) > 0.4;

  const safeTilt = Number.isFinite(tilt) ? tilt : 0;
  const safeKneeL = Number.isFinite(kneeL) ? kneeL : 180;
  const safeKneeR = Number.isFinite(kneeR) ? kneeR : 180;
  const safeKnee = Math.max(safeKneeL, safeKneeR);

  let label;
  if (safeTilt > 55) label = '躺卧';
  else if (safeTilt > 30) label = '倾斜';
  else if (safeKneeL < 120 && safeKneeR < 120) label = '蹲坐';
  else label = '站立';

  const standing = label === '站立' && fullBody;

  return { tilt: safeTilt, knee: safeKnee, kneeL: safeKneeL, kneeR: safeKneeR, fullBody, label, standing };
}

