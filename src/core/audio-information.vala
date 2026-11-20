[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Source audio metadata independent of negotiated speaker or HDMI output. */
    public sealed class AudioInformation : Object {
        /** Source audio codec identifier, or an empty string when unknown. */
        public string codec { get; construct; default = ""; }

        /** Original sample rate in hertz, zero when unknown. */
        public uint sample_rate_hz { get; construct; default = 0; }

        /** Number of source channels, zero when unknown. */
        public uint channels { get; construct; default = 0; }

        /** Object-audio format inferred from metadata, never an output guarantee. */
        public SpatialAudioFormat spatial_format {
            get;
            construct;
            default = SpatialAudioFormat.UNKNOWN;
        }

        /** Constructs an unprobed descriptor with unknown source fields. */
        public AudioInformation () {
            Object ();
        }
    }
}
