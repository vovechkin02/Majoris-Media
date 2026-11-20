[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** A source stream identifier and descriptive metadata, not a decoder. */
    public sealed class MediaTrack : Object {
        /** Backend-stable track identifier within the current source. */
        public string id { get; construct; }

        /** Video, audio, or subtitle stream category. */
        public TrackKind kind { get; construct; }

        /** Codec identifier, or an empty string if unknown. */
        public string codec { get; construct; default = ""; }

        /** Language tag, or an empty string if not declared. */
        public string language { get; construct; default = ""; }

        /** Human-readable source title, or an empty string if absent. */
        public string title { get; construct; default = ""; }

        /** Creates a descriptor for a single stream without inspecting its payload. */
        public MediaTrack (string id, TrackKind kind, string codec = "",
                           string language = "", string title = "") {
            Object (id: id, kind: kind, codec: codec, language: language, title: title);
        }
    }
}
