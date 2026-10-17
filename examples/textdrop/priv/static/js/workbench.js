// Workbench for one document: renders a page, lets the user draw areas on it,
// overlays the words and tables PdfExtractor finds, and shows the results in
// the tabs below the page. It talks to the JSON API in TextDrop.Controllers.Api.
// Coordinates are PDF points with the origin at the top-left of the page.
(() => {
    "use strict";

    const root = document.getElementById("workbench");
    if (!root) return;

    const documentId = root.dataset.documentId;
    const byId = (id) => document.getElementById(id);
    const el = {
        pageSelect: byId("page-select"),
        clearButton: byId("clear-button"),
        status: byId("status"),
        image: byId("page-image"),
        overlay: byId("overlay"),
        readout: byId("readout"),
        layoutToggle: byId("layout-toggle"),
        copyTextButton: byId("copy-text-button"),
        pageText: byId("page-text"),
        areasList: byId("areas-list"),
        areasEmpty: byId("areas-empty"),
        extractButton: byId("extract-button"),
        wordsButton: byId("words-button"),
        wordsSummary: byId("words-summary"),
        verticalStrategy: byId("vertical-strategy"),
        horizontalStrategy: byId("horizontal-strategy"),
        tablesButton: byId("tables-button"),
        tablesOutput: byId("tables-output"),
    };
    const tabs = Array.from(root.querySelectorAll("[role=tab]"));

    const ctx = el.overlay.getContext("2d");
    const rootStyle = getComputedStyle(document.documentElement);
    const rgb = (name) => rootStyle.getPropertyValue(name).trim();
    const colors = {
        area: `rgb(${rgb("--area-rgb")})`,
        areaFill: `rgba(${rgb("--area-rgb")}, 0.12)`,
        word: `rgb(${rgb("--word-rgb")})`,
        wordFill: `rgba(${rgb("--word-rgb")}, 0.18)`,
        table: `rgb(${rgb("--table-rgb")})`,
        tableFill: `rgba(${rgb("--table-rgb")}, 0.08)`,
    };
    const monoFont = rootStyle.getPropertyValue("--mono-font").trim() || "monospace";

    const state = {
        page: 0,
        size: { width: 612, height: 792 },
        areas: [], // { left, top, right, bottom, text: null | string }
        words: [],
        tables: [],
        drawing: null, // { start: { x, y }, current: { x, y } }
        hover: null,
    };

    // --- Helpers -------------------------------------------------------------

    const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
    const fmt = (number) => (Math.round(number * 10) / 10).toString();
    const describe = (box) =>
        `${fmt(box.left)}, ${fmt(box.top)} to ${fmt(box.right)}, ${fmt(box.bottom)}`;

    function element(tag, props = {}, children = []) {
        const node = document.createElement(tag);
        Object.assign(node, props);
        node.append(...children);
        return node;
    }

    const muted = (text) => element("p", { className: "muted", textContent: text });

    function setStatus(message, isError = false) {
        el.status.textContent = message;
        el.status.classList.toggle("error", isError);
    }

    async function run(label, task) {
        setStatus(label);
        try {
            await task();
            setStatus("");
        } catch (error) {
            setStatus(error.message, true);
        }
    }

    async function api(path, options = {}) {
        const url = `/api/documents/${documentId}/pages/${state.page}/${path}`;
        const response = await fetch(url, options);
        let body = null;
        try {
            body = await response.json();
        } catch (_error) {
            body = null;
        }
        if (!response.ok) {
            const message = body && body.message;
            throw new Error(message || `Request failed with status ${response.status}.`);
        }
        return body;
    }

    function flash(button, text) {
        const original = button.textContent;
        button.textContent = text;
        setTimeout(() => {
            button.textContent = original;
        }, 1500);
    }

    // --- Tabs ----------------------------------------------------------------

    function selectTab(name) {
        tabs.forEach((tab) => {
            const selected = tab.dataset.tab === name;
            tab.setAttribute("aria-selected", String(selected));
            tab.tabIndex = selected ? 0 : -1;
            byId(`panel-${tab.dataset.tab}`).hidden = !selected;
        });
    }

    function setCount(name, count) {
        const badge = byId(`${name}-count`);
        if (badge) badge.textContent = count ? String(count) : "";
    }

    tabs.forEach((tab, index) => {
        tab.addEventListener("click", () => selectTab(tab.dataset.tab));
        tab.addEventListener("keydown", (event) => {
            const step = { ArrowRight: 1, ArrowLeft: -1, Home: -index, End: tabs.length - 1 - index }[event.key];
            if (step === undefined) return;
            event.preventDefault();
            const next = tabs[(index + step + tabs.length) % tabs.length];
            selectTab(next.dataset.tab);
            next.focus();
        });
    });

    // --- Geometry ------------------------------------------------------------

    function scale() {
        return {
            x: el.overlay.clientWidth / state.size.width,
            y: el.overlay.clientHeight / state.size.height,
        };
    }

    function toPoints(event) {
        const rect = el.overlay.getBoundingClientRect();
        const s = scale();
        return {
            x: clamp((event.clientX - rect.left) / s.x, 0, state.size.width),
            y: clamp((event.clientY - rect.top) / s.y, 0, state.size.height),
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

    const boxFrom = (a, b) => ({
        left: Math.min(a.x, b.x),
        top: Math.min(a.y, b.y),
        right: Math.max(a.x, b.x),
        bottom: Math.max(a.y, b.y),
    });

    const contains = (box, point) =>
        point.x >= box.left && point.x <= box.right && point.y >= box.top && point.y <= box.bottom;

    function resizeOverlay() {
        const width = el.image.clientWidth;
        const height = el.image.clientHeight;
        const dpr = window.devicePixelRatio || 1;
        el.overlay.width = Math.round(width * dpr);
        el.overlay.height = Math.round(height * dpr);
        el.overlay.style.width = `${width}px`;
        el.overlay.style.height = `${height}px`;
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        draw();
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
        ctx.clearRect(0, 0, el.overlay.clientWidth, el.overlay.clientHeight);
        state.words.forEach((word) => strokeBox(word, colors.word, { width: 1 }));
        if (state.hover) strokeBox(state.hover, colors.word, { width: 2, fill: colors.wordFill });
        state.tables.forEach((table, i) =>
            strokeBox(table, colors.table, { width: 2, fill: colors.tableFill, label: `T${i + 1}` }),
        );
        state.areas.forEach((area, i) =>
            strokeBox(area, colors.area, { width: 2, fill: colors.areaFill, label: `${i + 1}` }),
        );
        if (state.drawing) {
            strokeBox(boxFrom(state.drawing.start, state.drawing.current), colors.area, { dashed: true });
        }
    }

    // --- Pointer interaction -------------------------------------------------

    el.overlay.addEventListener("pointerdown", (event) => {
        if (event.button !== 0) return;
        el.overlay.setPointerCapture(event.pointerId);
        const point = toPoints(event);
        state.drawing = { start: point, current: point };
        draw();
    });

    el.overlay.addEventListener("pointermove", (event) => {
        const point = toPoints(event);
        if (state.drawing) {
            state.drawing.current = point;
            draw();
        } else {
            const hit = state.words.find((word) => contains(word, point)) || null;
            if (hit !== state.hover) {
                state.hover = hit;
                draw();
            }
        }
        el.readout.textContent = readoutFor(point);
    });

    el.overlay.addEventListener("pointerup", (event) => {
        if (!state.drawing) return;
        const box = boxFrom(state.drawing.start, toPoints(event));
        state.drawing = null;
        if (box.right - box.left >= 2 && box.bottom - box.top >= 2) {
            state.areas.push({ ...box, text: null });
            renderAreas();
            selectTab("areas");
        }
        draw();
    });

    el.overlay.addEventListener("pointerleave", () => {
        if (state.hover) {
            state.hover = null;
            draw();
        }
        el.readout.textContent = "";
    });

    function readoutFor(point) {
        let text = `x ${fmt(point.x)}  y ${fmt(point.y)} pt`;
        if (state.drawing) {
            text += `   drawing ${describe(boxFrom(state.drawing.start, state.drawing.current))}`;
        } else if (state.hover) {
            const word = state.hover;
            const font = [word.font_name, word.font_size ? `${fmt(word.font_size)} pt` : null]
                .filter(Boolean)
                .join(" ");
            text += `   "${word.text}"  ${font}`;
        }
        return text;
    }

    // --- Areas ---------------------------------------------------------------

    function renderAreas() {
        const items = state.areas.map((area, i) => {
            const remove = element("button", {
                type: "button",
                className: "secondary small",
                textContent: "Remove",
            });
            remove.addEventListener("click", () => {
                state.areas.splice(i, 1);
                renderAreas();
                draw();
            });
            const head = element("div", { className: "area-head" }, [
                element("strong", { textContent: `Area ${i + 1}` }),
                element("code", { textContent: describe(area) }),
                remove,
            ]);
            const children = [head];
            if (area.text !== null) {
                children.push(element("pre", { textContent: area.text || "(no text in this area)" }));
            }
            return element("li", {}, children);
        });
        el.areasList.replaceChildren(...items);
        el.areasEmpty.hidden = state.areas.length > 0;
        el.extractButton.disabled = state.areas.length === 0;
        setCount("areas", state.areas.length);
    }

    el.extractButton.addEventListener("click", () =>
        run("Extracting text in areas", async () => {
            const areas = state.areas.map(({ left, top, right, bottom }) => ({ left, top, right, bottom }));
            const response = await api("areas", {
                method: "POST",
                headers: { "content-type": "application/json" },
                body: JSON.stringify({ areas }),
            });
            response.areas.forEach((result, i) => {
                if (state.areas[i]) state.areas[i].text = result.text;
            });
            renderAreas();
        }),
    );

    // --- Page text -----------------------------------------------------------

    async function loadText() {
        const { text } = await api(`text?layout=${el.layoutToggle.checked}`);
        el.pageText.textContent = text;
    }

    el.layoutToggle.addEventListener("change", () => run("Loading page text", loadText));

    el.copyTextButton.addEventListener("click", async () => {
        try {
            await navigator.clipboard.writeText(el.pageText.textContent);
            flash(el.copyTextButton, "Copied!");
        } catch (_error) {
            setStatus("The clipboard is not available in this browser.", true);
        }
    });

    // --- Words ---------------------------------------------------------------

    el.wordsButton.addEventListener("click", () =>
        run("Loading words", async () => {
            const { words } = await api("words");
            state.words = words;
            const fonts = new Set(words.map((word) => word.font_name));
            el.wordsSummary.textContent = words.length
                ? `${words.length} words in ${fonts.size} font${fonts.size === 1 ? "" : "s"}. Hover a word on the page to see its font and size.`
                : "No words on this page.";
            setCount("words", words.length);
            draw();
        }),
    );

    // --- Tables --------------------------------------------------------------

    el.tablesButton.addEventListener("click", () =>
        run("Finding tables", async () => {
            const query = new URLSearchParams({
                vertical_strategy: el.verticalStrategy.value,
                horizontal_strategy: el.horizontalStrategy.value,
            });
            const { tables } = await api(`tables?${query}`);
            state.tables = tables;
            renderTables();
            setCount("tables", tables.length);
            draw();
        }),
    );

    function renderTables() {
        if (!state.tables.length) {
            el.tablesOutput.replaceChildren(muted("No tables found with these strategies."));
            return;
        }
        const figures = state.tables.map((table, i) => {
            const rows = table.rows.map((row) =>
                element("tr", {}, row.map((cell) => element("td", { textContent: cell == null ? "" : String(cell) }))),
            );
            return element("figure", {}, [
                element("figcaption", {
                    textContent: `Table ${i + 1}: ${table.rows.length} rows, ${describe(table)}`,
                }),
                element("table", {}, [element("tbody", {}, rows)]),
            ]);
        });
        el.tablesOutput.replaceChildren(...figures);
    }

    // --- Page ----------------------------------------------------------------

    function clearOverlays() {
        state.areas = [];
        state.words = [];
        state.tables = [];
        state.hover = null;
        state.drawing = null;
        renderAreas();
        el.wordsSummary.textContent =
            "Not loaded. Words are drawn over the page; hover one to see its font and size.";
        el.tablesOutput.replaceChildren(muted("Not loaded."));
        setCount("words", 0);
        setCount("tables", 0);
        el.readout.textContent = "Drag on the page to draw an area.";
        draw();
    }

    el.clearButton.addEventListener("click", clearOverlays);

    async function loadPage() {
        const option = el.pageSelect.selectedOptions[0];
        if (!option) {
            setStatus("This document has no pages.", true);
            return;
        }
        state.page = Number(option.value);
        state.size = { width: Number(option.dataset.width), height: Number(option.dataset.height) };
        clearOverlays();
        el.pageText.textContent = "";

        await run("Rendering page", async () => {
            el.image.src = `/api/documents/${documentId}/pages/${state.page}/image?width=1400`;
            try {
                await el.image.decode();
            } catch (_error) {
                throw new Error("The page could not be rendered.");
            }
            resizeOverlay();
        });
        await run("Loading page text", loadText);
    }

    el.pageSelect.addEventListener("change", loadPage);

    root.querySelectorAll("[data-show-page]").forEach((button) => {
        button.addEventListener("click", () => {
            el.pageSelect.value = button.dataset.showPage;
            loadPage();
            window.scrollTo({ top: root.offsetTop, behavior: "smooth" });
        });
    });

    new ResizeObserver(() => resizeOverlay()).observe(el.image);
    loadPage();
})();
