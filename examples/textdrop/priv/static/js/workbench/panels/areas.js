// The Areas tab: boxes the user drew on the page and the text inside them.

import { byId, cssColor, element } from "../dom.js";
import { describe } from "../geometry.js";

export function createAreasPanel({ client, overlay, tabs, status, getPage }) {
    const list = byId("areas-list");
    const empty = byId("areas-empty");
    const extractButton = byId("extract-button");
    const areas = []; // { left, top, right, bottom, text: null | string }

    overlay.addLayer({
        color: cssColor("--area-rgb"),
        fill: cssColor("--area-rgb", 0.12),
        width: 2,
        label: (i) => `${i + 1}`,
        boxes: () => areas,
    });

    function render() {
        const items = areas.map((area, i) => {
            const remove = element("button", {
                type: "button",
                className: "secondary small",
                textContent: "Remove",
            });
            remove.addEventListener("click", () => {
                areas.splice(i, 1);
                render();
                overlay.draw();
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
        list.replaceChildren(...items);
        empty.hidden = areas.length > 0;
        extractButton.disabled = areas.length === 0;
        tabs.setCount("areas", areas.length);
    }

    extractButton.addEventListener("click", () =>
        status.run("Extracting text in areas", async () => {
            const boxes = areas.map(({ left, top, right, bottom }) => ({ left, top, right, bottom }));
            const response = await client.areas(getPage(), boxes);
            response.areas.forEach((result, i) => {
                if (areas[i]) areas[i].text = result.text;
            });
            render();
        }),
    );

    render();

    return {
        add(box) {
            areas.push({ ...box, text: null });
            render();
            tabs.select("areas");
            overlay.draw();
        },
        clear() {
            areas.length = 0;
            render();
        },
    };
}
