// Boxes are { left, top, right, bottom } in PDF points, origin top-left.

export const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

export const fmt = (number) => (Math.round(number * 10) / 10).toString();

export const describe = (box) =>
    `${fmt(box.left)}, ${fmt(box.top)} to ${fmt(box.right)}, ${fmt(box.bottom)}`;

export const boxFrom = (a, b) => ({
    left: Math.min(a.x, b.x),
    top: Math.min(a.y, b.y),
    right: Math.max(a.x, b.x),
    bottom: Math.max(a.y, b.y),
});

export const contains = (box, point) =>
    point.x >= box.left && point.x <= box.right && point.y >= box.top && point.y <= box.bottom;

export const size = (box) => ({ width: box.right - box.left, height: box.bottom - box.top });
