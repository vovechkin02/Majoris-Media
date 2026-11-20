[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Caller-requested playback policies; availability is negotiated separately. */
    public sealed class PlaybackOptions : Object {
        /** Audio policy that must not force unsupported device passthrough. */
        public AudioOutputPolicy audio_policy {
            get;
            set;
            default = AudioOutputPolicy.AUTO;
        }

        /** HDR policy that must not be confused with actual HDR presentation. */
        public HdrOutputPolicy hdr_policy {
            get;
            set;
            default = HdrOutputPolicy.AUTO;
        }

        /** Whether seek requests should prefer precision over fast keyframe seeks. */
        public bool accurate_seek { get; set; default = true; }

        /** Creates the default safe playback policy. */
        public PlaybackOptions () {
            Object ();
        }
    }
}
