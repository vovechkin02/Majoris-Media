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

        /** Whether libmpv currently selects this track for output. */
        public bool selected { get; construct; default = false; }

        /** Whether this track is identified as the source's default stream. */
        public bool is_default { get; construct; default = false; }

        /** Whether the source marks this track as forced. */
        public bool forced { get; construct; default = false; }

        /** Whether the stream is provided outside the main media container. */
        public bool external { get; construct; default = false; }

        /** Creates a descriptor for a single stream without inspecting its payload. */
        public MediaTrack (string id, TrackKind kind, string codec = "",
                           string language = "", string title = "",
                           bool selected = false, bool is_default = false,
                           bool forced = false, bool external = false) {
            Object (id: id, kind: kind, codec: codec, language: language, title: title,
                    selected: selected, is_default: is_default, forced: forced,
                    external: external);
        }
    }
}
