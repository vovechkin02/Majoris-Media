[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Immutable-identity media probe result; stream lists are read-only to consumers. */
    public sealed class MediaDescription : Object {
        /** The exact source for which this description was obtained. */
        public MediaSource source { get; construct; }

        /** Stream duration in microseconds, or -1 if not established. */
        public int64 duration_us { get; construct; default = -1; }

        /** Metadata track descriptions in source order. */
        public ListModel tracks {
            get {
                return track_store;
            }
        }

        /** Chapter markers in source order. */
        public ListModel chapters {
            get {
                return chapter_store;
            }
        }

        /** Owns the track list backing the read-only public model. */
        private ListStore track_store;

        /** Owns the chapter list backing the read-only public model. */
        private ListStore chapter_store;

        /** Creates an initially empty metadata result for a particular source. */
        public MediaDescription (MediaSource source) {
            Object (source: source);
            track_store = new ListStore (typeof (MediaTrack));
            chapter_store = new ListStore (typeof (MediaChapter));
        }

        /** Adds a stream descriptor in the order returned by the backend. */
        internal void append_track (MediaTrack track) {
            track_store.append (track);
        }

        /** Adds a chapter descriptor in the order returned by the backend. */
        internal void append_chapter (MediaChapter chapter) {
            chapter_store.append (chapter);
        }
    }
}
