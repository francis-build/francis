// The Tables tab: tables found with the chosen strategies, outlined on the page
// and rendered as rows.

import { byId, cssColor, element, muted } from "../dom.js";
import { describe } from "../geometry.js";

export function createTablesPanel({ client, overlay, tabs, status, getPage }) {
    const button = byId("tables-button");
    const vertical = byId("vertical-strategy");
    const horizontal = byId("horizontal-strategy");
    const output = byId("tables-output");
    let tables = [];

    overlay.addLayer({
        color: cssColor("--table-rgb"),
        fill: cssColor("--table-rgb", 0.08),
        width: 2,
        label: (i) => `T${i + 1}`,
        boxes: () => tables,
    });

    function render() {
        if (!tables.length) {
            output.replaceChildren(muted("No tables found with these strategies."));
            return;
        }
        const figures = tables.map((table, i) => {
            const rows = table.rows.map((row) =>
                element(
                    "tr",
                    {},
                    row.map((cell) => element("td", { textContent: cell == null ? "" : String(cell) })),
                ),
            );
            return element("figure", {}, [
                element("figcaption", {
                    textContent: `Table ${i + 1}: ${table.rows.length} rows, ${describe(table)}`,
                }),
                element("table", {}, [element("tbody", {}, rows)]),
            ]);
        });
        output.replaceChildren(...figures);
    }

    button.addEventListener("click", () =>
        status.run("Finding tables", async () => {
            const strategies = { vertical_strategy: vertical.value, horizontal_strategy: horizontal.value };
            ({ tables } = await client.tables(getPage(), strategies));
            render();
            tabs.setCount("tables", tables.length);
            overlay.draw();
        }),
    );

    return {
        clear() {
            tables = [];
            output.replaceChildren(muted("Not loaded."));
            tabs.setCount("tables", 0);
        },
    };
}
