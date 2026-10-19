// Entry point of the document workbench: wires the toolbar, the page viewer
// and the panels together. Each panel owns its controls, its results and the
// overlay layer it draws; this file only knows which page is shown.

import { byId, cssColor } from "./dom.js";
import { createClient } from "./client.js";
import { createStatus } from "./status.js";
import { createTabs } from "./tabs.js";
import { createOverlay } from "./overlay.js";
import { createTextPanel } from "./panels/text.js";
import { createWordsPanel } from "./panels/words.js";
import { createTablesPanel } from "./panels/tables.js";
import { createAreasPanel } from "./panels/areas.js";

// Ask before a destructive form, such as deleting the document, is submitted.
document.querySelectorAll("form[data-confirm]").forEach((form) => {
    form.addEventListener("submit", (event) => {
        if (!window.confirm(form.dataset.confirm)) event.preventDefault();
    });
});

const root = byId("workbench");

if (root) {
    const client = createClient(root.dataset.documentId);
    const status = createStatus(byId("status"));
    const tabs = createTabs(root);
    const pageSelect = byId("page-select");
    const image = byId("page-image");

    let page = 0;
    const getPage = () => page;

    let areasPanel = null;
    const overlay = createOverlay({
        image,
        canvas: byId("overlay"),
        readout: byId("readout"),
        idleText: "Drag on the page to draw an area.",
        drawingColor: cssColor("--area-rgb"),
        onArea: (box) => areasPanel.add(box),
    });

    const deps = { client, overlay, tabs, status, getPage };
    const textPanel = createTextPanel(deps);
    // Layers draw in creation order, so areas are created last to sit on top.
    const wordsPanel = createWordsPanel(deps);
    const tablesPanel = createTablesPanel(deps);
    areasPanel = createAreasPanel(deps);
    const overlayPanels = [wordsPanel, tablesPanel, areasPanel];

    function clearOverlays() {
        overlayPanels.forEach((panel) => panel.clear());
        overlay.reset();
    }

    async function loadPage() {
        const option = pageSelect.selectedOptions[0];
        if (!option) {
            status.set("This document has no pages.", true);
            return;
        }
        page = Number(option.value);
        overlay.setPageSize(Number(option.dataset.width), Number(option.dataset.height));
        clearOverlays();
        textPanel.clear();

        await status.run("Rendering page", async () => {
            image.src = client.imageUrl(page);
            try {
                await image.decode();
            } catch (_error) {
                throw new Error("The page could not be rendered.");
            }
            overlay.resize();
        });
        await textPanel.load();
    }

    byId("clear-button").addEventListener("click", clearOverlays);
    pageSelect.addEventListener("change", loadPage);
    root.querySelectorAll("[data-show-page]").forEach((button) => {
        button.addEventListener("click", () => {
            pageSelect.value = button.dataset.showPage;
            loadPage();
            window.scrollTo({ top: root.offsetTop, behavior: "smooth" });
        });
    });

    loadPage();
}
