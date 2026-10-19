// Small DOM helpers shared by the workbench modules.

export const byId = (id) => document.getElementById(id);

export function element(tag, props = {}, children = []) {
    const node = document.createElement(tag);
    Object.assign(node, props);
    node.append(...children);
    return node;
}

export const muted = (text) => element("p", { className: "muted", textContent: text });

export function flash(button, text, ms = 1500) {
    const original = button.textContent;
    button.textContent = text;
    setTimeout(() => {
        button.textContent = original;
    }, ms);
}

// A colour from an `--x-rgb` custom property holding an RGB triplet.
export function cssColor(variable, alpha = null) {
    const rgb = getComputedStyle(document.documentElement).getPropertyValue(variable).trim();
    return alpha === null ? `rgb(${rgb})` : `rgba(${rgb}, ${alpha})`;
}
