[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Defines the future headless metadata-probing API independently of playback. */
    public sealed class MediaProbe : Object {
        /** Creates a reusable metadata probe with no active source. */
        public MediaProbe () {
            Object ();
        }

        /** Reports a missing metadata engine, without inventing stream information. */
        public async MediaDescription inspect_async (MediaSource source,
                                                     Cancellable? cancellable = null)
                                                     throws Error {
            cancellable?.set_error_if_cancelled ();
            Idle.add (inspect_async.callback);
            yield;
            cancellable?.set_error_if_cancelled ();
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }
    }
}
