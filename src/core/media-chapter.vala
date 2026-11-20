[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** A navigation chapter with a microsecond timestamp within its source. */
    public sealed class MediaChapter : Object {
        /** Zero-based chapter order within the identified source. */
        public uint index { get; construct; }

        /** Start offset in microseconds from the beginning of the source. */
        public int64 start_us { get; construct; }

        /** Chapter title; empty when the source does not supply one. */
        public string title { get; construct; default = ""; }

        /** Creates a chapter descriptor without changing playback. */
        public MediaChapter (uint index, int64 start_us, string title = "") {
            Object (index: index, start_us: start_us, title: title);
        }
    }
}
