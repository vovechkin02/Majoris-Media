[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Discovered mpv output endpoint; availability does not establish codec support. */
    public sealed class AudioDevice : Object {
        /** Exact mpv device token, never a user-facing display label. */
        public string id { get; construct; }

        /** Descriptive device name, sanitized by the native engine. */
        public string description { get; construct; }

        /** Whether the output is currently selected by the engine. */
        public bool selected { get; construct; default = false; }

        /** Constructs an immutable device entry from one engine enumeration. */
        public AudioDevice (string id, string description, bool selected = false) {
            Object (id: id, description: description, selected: selected);
        }
    }
}
