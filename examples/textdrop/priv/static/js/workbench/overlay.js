// The canvas over the page image. It draws the boxes of every registered
// layer, reports the box under the pointer, and lets the user drag out a new
// area. A layer is { color, width, fill?, label?(i), boxes(), hoverable?,
// hoverFill?, describe?(box) }; layers draw in registration order.

import { boxFrom, contains, describe, fmt, size } from "./geometry.js";

const MIN_AREA_SIZE = 2;

export function createOverlay({ image, canvas, readout, idleText, drawingColor, onArea }) {
    const ctx = canvas.getContext("2d");
    const monoFont =
        getComputedStyle(document.documentElement).getPropertyValue("--mono-font").trim() || "monospace";
    const layers = [];
    let pageSize = { width: 612, height: 792 };
    let drawing = null; // { start: { x, y }, current: { x, y } }
    let hover = null; // { layer, box }

    // --- Geometry ------------------------------------------------------------

    const scale = () => ({
        x: canvas.clientWidth / pageSize.width,
        y: canvas.clientHeight / pageSize.height,
    });

    function toPoints(event) {
        const rect = canvas.getBoundingClientRect();
        const s = scale();
        return {
            x: Math.min(pageSize.width, Math.max(0, (event.clientX - rect.left) / s.x)),
            y: Math.min(pageSize.height, Math.max(0, (event.clientY - rect.top) / s.y)),
        };
    }

    function toPixels(box) {
        const s = scale();
        return {
            x: box.left * s.x,
            y: box.top * s.y,
            w: (box.right - box.left) * s.x,
            h: (box.bottom - box.top) * s.y,
        };
    }

    // --- Drawing -------------------------------------------------------------

    function strokeBox(box, stroke, { width = 1.5, fill = null, dashed = false, label = null } = {}) {
        const r = toPixels(box);
        ctx.save();
        ctx.lineWidth = width;
        ctx.strokeStyle = stroke;
        ctx.setLineDash(dashed ? [6, 4] : []);
        if (fill) {
            ctx.fillStyle = fill;
            ctx.fillRect(r.x, r.y, r.w, r.h);
        }
        ctx.strokeRect(r.x, r.y, r.w, r.h);
        if (label) drawLabel(label, r, stroke);
        ctx.restore();
    }

    function drawLabel(text, r, color) {
        ctx.font = `600 11px ${monoFont}`;
        const width = ctx.measureText(text).width + 8;
        const height = 16;
        // Above the box when there is room, otherwise inside its top edge.
        const y = r.y >= height ? r.y - height : r.y;
        ctx.fillStyle = color;
        ctx.fillRect(r.x, y, width, height);
        ctx.fillStyle = "#fff";
        ctx.textBaseline = "middle";
        ctx.fillText(text, r.x + 4, y + height / 2);
    }

    function draw() {
        ctx.clearRect(0, 0, canvas.clientWidth, canvas.clientHeight);
        for (const layer of layers) {
            layer.boxes().forEach((box, i) =>
                strokeBox(box, layer.color, {
                    width: layer.width,
                    fill: layer.fill,
                    label: layer.label ? layer.label(i) : null,
                }),
            );
        }
        if (hover) strokeBox(hover.box, hover.layer.color, { width: 2, fill: hover.layer.hoverFill });
        if (drawing) strokeBox(boxFrom(drawing.start, drawing.current), drawingColor, { dashed: true });
    }

    function resize() {
        const dpr = window.devicePixelRatio || 1;
        const { clientWidth: width, clientHeight: height } = image;
        canvas.width = Math.round(width * dpr);
        canvas.height = Math.round(height * dpr);
        canvas.style.width = `${width}px`;
        canvas.style.height = `${height}px`;
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        draw();
    }

    // --- Pointer -------------------------------------------------------------

    function findHover(point) {
        for (const layer of layers) {
            if (!layer.hoverable) continue;
            const box = layer.boxes().find((candidate) => contains(candidate, point));
            if (box) return { layer, box };
        }
        return null;
    }

    function readoutFor(point) {
        let text = `x ${fmt(point.x)}  y ${fmt(point.y)} pt`;
        if (drawing) {
            text += `   drawing ${describe(boxFrom(drawing.start, drawing.current))}`;
        } else if (hover && hover.layer.describe) {
            text += `   ${hover.layer.describe(hover.box)}`;
        }
        return text;
    }

    canvas.addEventListener("pointerdown", (event) => {
        if (event.button !== 0) return;
        canvas.setPointerCapture(event.pointerId);
        const point = toPoints(event);
        drawing = { start: point, current: point };
        draw();
    });

    canvas.addEventListener("pointermove", (event) => {
        const point = toPoints(event);
        if (drawing) {
            drawing.current = point;
            draw();
        } else {
            const found = findHover(point);
            if ((found && found.box) !== (hover && hover.box)) {
                hover = found;
                draw();
            }
        }
        readout.textContent = readoutFor(point);
    });

    canvas.addEventListener("pointerup", (event) => {
        if (!drawing) return;
        const box = boxFrom(drawing.start, toPoints(event));
        drawing = null;
        const { width, height } = size(box);
        if (width >= MIN_AREA_SIZE && height >= MIN_AREA_SIZE) onArea(box);
        draw();
    });

    canvas.addEventListener("pointerleave", () => {
        if (hover) {
            hover = null;
            draw();
        }
        readout.textContent = idleText;
    });

    new ResizeObserver(resize).observe(image);

    // --- API -----------------------------------------------------------------

    function addLayer(layer) {
        layers.push(layer);
        return layer;
    }

    function setPageSize(width, height) {
        pageSize = { width, height };
    }

    function reset() {
        hover = null;
        drawing = null;
        readout.textContent = idleText;
        draw();
    }

    return { addLayer, setPageSize, reset, resize, draw };
}
