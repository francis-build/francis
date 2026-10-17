// The Text tab: the text of the page, with or without its layout.

import { byId, flash } from "../dom.js";

export function createTextPanel({ client, status, getPage }) {
    const toggle = byId("layout-toggle");
    const output = byId("page-text");
    const copyButton = byId("copy-text-button");

    async function fetchText() {
        const { text } = await client.text(getPage(), toggle.checked);
        output.textContent = text;
    }

    const load = () => status.run("Loading page text", fetchText);

    toggle.addEventListener("change", load);

    copyButton.addEventListener("click", async () => {
        try {
            await navigator.clipboard.writeText(output.textContent);
            flash(copyButton, "Copied!");
        } catch (_error) {
            status.set("The clipboard is not available in this browser.", true);
        }
    });

    return {
        load,
        clear() {
            output.textContent = "";
        },
    };
}
