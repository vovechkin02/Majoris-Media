[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Read-only observations from a separately windowed gpu-next player. */
    public sealed class GpuNextPlaybackStatus : Object {
        /** Whether the player reports a user-visible paused state. */
        public bool paused { get; construct; default = false; }

        /** Actual player position in microseconds, or -1 if unavailable. */
        public int64 position_us { get; construct; default = -1; }

        /** Actual mpv video output driver, if exposed by the running engine. */
        public string video_output { get; construct; default = ""; }

        /** Source video color primaries from mpv, not the display color mode. */
        public string source_primaries { get; construct; default = ""; }

        /** Source video transfer characteristic from mpv, not verified HDR scanout. */
        public string source_transfer { get; construct; default = ""; }

        /** IPC observations alone never prove a compositor's native HDR output. */
        public CapabilityStatus native_hdr { get; construct; default = CapabilityStatus.UNVERIFIED; }

        /** Creates an observation with explicit evidence, rather than assumed output. */
        public GpuNextPlaybackStatus (bool paused, int64 position_us, string video_output,
                                      string source_primaries, string source_transfer) {
            Object (
                paused: paused,
                position_us: position_us,
                video_output: video_output,
                source_primaries: source_primaries,
                source_transfer: source_transfer
            );
        }
    }
}
