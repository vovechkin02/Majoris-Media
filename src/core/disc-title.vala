[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Immutable optical-disc title or playlist discovered from the playback engine. */
    public sealed class DiscTitle : Object {
        /** Zero-based title/edition index used for subsequent selection. */
        public uint index { get; construct; }

        /** Human-readable title as reported by libmpv, which may be empty. */
        public string name { get; construct; }

        /** Duration in microseconds, or zero when unknown. */
        public int64 duration_us { get; construct; }

        /** Whether this is the current title according to the playback engine. */
        public bool selected { get; construct; }

        /** Creates a snapshot item without retaining native decoder memory. */
        public DiscTitle (uint index, string name, int64 duration_us, bool selected) {
            Object (index: index, name: name, duration_us: duration_us, selected: selected);
        }
    }
}
