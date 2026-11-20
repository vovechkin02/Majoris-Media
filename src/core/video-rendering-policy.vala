[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Validates a closed renderer policy before constructing an engine. */
    internal sealed class VideoRenderingPolicy : Object {
        /** Converts stable user-facing tone mapping to an mpv option token. */
        internal static string tone_mapping_option (ToneMappingAlgorithm algorithm) throws Error {
            switch (algorithm) {
            case ToneMappingAlgorithm.AUTO:
                return "auto";
            case ToneMappingAlgorithm.BT2390:
                return "bt.2390";
            case ToneMappingAlgorithm.MOBIUS:
                return "mobius";
            case ToneMappingAlgorithm.HABLE:
                return "hable";
            default:
                throw new MediaError.INVALID_ARGUMENT ("Unknown SDR tone mapping algorithm");
            }
        }

        /** Converts the quality policy to a fixed, bounded debanding configuration. */
        internal static bool should_deband (VideoQualityPolicy quality) throws Error {
            switch (quality) {
            case VideoQualityPolicy.BALANCED:
                return false;
            case VideoQualityPolicy.HIGH_QUALITY:
                return true;
            default:
                throw new MediaError.INVALID_ARGUMENT ("Unknown video quality policy");
            }
        }

        /** Validates video settings without probing or opening a playback device. */
        internal static void validate (PlaybackOptions options) throws Error {
            tone_mapping_option (options.tone_mapping);
            should_deband (options.video_quality);
        }
    }
}
