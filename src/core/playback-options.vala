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

        /** Safe or source-preferred multichannel PCM mixing/negotiation. */
        public PcmChannelPolicy pcm_channel_policy {
            get;
            set;
            default = PcmChannelPolicy.SYSTEM_DEFAULT;
        }

        /** Exact libmpv audio device identifier; auto follows the system default. */
        public string audio_device_id { get; set; default = "auto"; }

        /** Codec list approved by the application/user for the selected receiver. */
        public AudioPassthroughCodec passthrough_codecs {
            get;
            set;
            default = AudioPassthroughCodec.NONE;
        }

        /** HDR policy that must not be confused with actual HDR presentation. */
        public HdrOutputPolicy hdr_policy {
            get;
            set;
            default = HdrOutputPolicy.AUTO;
        }

        /** Selected renderer-compatible SDR tone mapping algorithm. */
        public ToneMappingAlgorithm tone_mapping {
            get;
            set;
            default = ToneMappingAlgorithm.AUTO;
        }

        /** Optional bounded debanding, not a promise of GPU performance. */
        public VideoQualityPolicy video_quality {
            get;
            set;
            default = VideoQualityPolicy.BALANCED;
        }

        /** Whether seek requests should prefer precision over fast keyframe seeks. */
        public bool accurate_seek { get; set; default = true; }

        /** Creates the default safe playback policy. */
        public PlaybackOptions () {
            Object ();
        }
    }
}
