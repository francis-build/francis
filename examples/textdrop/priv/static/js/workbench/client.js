// Talks to TextDrop.Controllers.Api for one document.

export function createClient(documentId) {
    const url = (page, path) => `/api/documents/${documentId}/pages/${page}/${path}`;

    async function request(page, path, options = {}) {
        const response = await fetch(url(page, path), options);
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

    return {
        imageUrl: (page) => url(page, "image"),
        text: (page, layout) => request(page, `text?layout=${layout}`),
        words: (page) => request(page, "words"),
        tables: (page, strategies) => request(page, `tables?${new URLSearchParams(strategies)}`),
        areas: (page, areas) =>
            request(page, "areas", {
                method: "POST",
                headers: { "content-type": "application/json" },
                body: JSON.stringify({ areas }),
            }),
    };
}
