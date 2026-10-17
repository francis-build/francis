// The status line in the toolbar: what is running, or what went wrong.

export function createStatus(node) {
    function set(message, isError = false) {
        node.textContent = message;
        node.classList.toggle("error", isError);
    }

    async function run(label, task) {
        set(label);
        try {
            await task();
            set("");
        } catch (error) {
            set(error.message, true);
        }
    }

    return { set, run };
}
