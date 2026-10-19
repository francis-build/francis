// Accessible tabs: [role=tab] buttons controlling [role=tabpanel] sections.

export function createTabs(root) {
    const tabs = Array.from(root.querySelectorAll("[role=tab]"));
    const panelOf = (tab) => document.getElementById(tab.getAttribute("aria-controls"));

    function select(name) {
        tabs.forEach((tab) => {
            const selected = tab.dataset.tab === name;
            tab.setAttribute("aria-selected", String(selected));
            tab.tabIndex = selected ? 0 : -1;
            panelOf(tab).hidden = !selected;
        });
    }

    function setCount(name, count) {
        const badge = document.getElementById(`${name}-count`);
        if (badge) badge.textContent = count ? String(count) : "";
    }

    tabs.forEach((tab, index) => {
        tab.addEventListener("click", () => select(tab.dataset.tab));
        tab.addEventListener("keydown", (event) => {
            const steps = { ArrowRight: 1, ArrowLeft: -1, Home: -index, End: tabs.length - 1 - index };
            const step = steps[event.key];
            if (step === undefined) return;
            event.preventDefault();
            const next = tabs[(index + step + tabs.length) % tabs.length];
            select(next.dataset.tab);
            next.focus();
        });
    });

    return { select, setCount };
}
