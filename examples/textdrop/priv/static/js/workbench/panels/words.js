// The Words tab: every word on the page, drawn over it with font details on hover.

import { byId, cssColor } from "../dom.js";
import { fmt } from "../geometry.js";

export function createWordsPanel({ client, overlay, tabs, status, getPage }) {
    const button = byId("words-button");
    const summary = byId("words-summary");
    const notLoaded = summary.textContent;
    let words = [];

    overlay.addLayer({
        color: cssColor("--word-rgb"),
        hoverFill: cssColor("--word-rgb", 0.18),
        width: 1,
        hoverable: true,
        boxes: () => words,
        describe(word) {
            const font = [word.font_name, word.font_size ? `${fmt(word.font_size)} pt` : null]
                .filter(Boolean)
                .join(" ");
            return `"${word.text}"  ${font}`;
        },
    });

    button.addEventListener("click", () =>
        status.run("Loading words", async () => {
            ({ words } = await client.words(getPage()));
            const fonts = new Set(words.map((word) => word.font_name));
            summary.textContent = words.length
                ? `${words.length} words in ${fonts.size} font${fonts.size === 1 ? "" : "s"}. Hover a word on the page to see its font and size.`
                : "No words on this page.";
            tabs.setCount("words", words.length);
            overlay.draw();
        }),
    );

    return {
        clear() {
            words = [];
            summary.textContent = notLoaded;
            tabs.setCount("words", 0);
        },
    };
}
