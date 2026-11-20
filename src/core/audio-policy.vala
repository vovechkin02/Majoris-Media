namespace MediaKit {
    /** Typed policy-to-engine translation, with no arbitrary codec token injection. */
    internal class AudioPolicy : Object {
        /** Formats accepted by this mpv version, without presuming device support. */
        private const int CODEC_MASK = 31;

        /** Validates a receiver-specific request before allocating a playback engine. */
        internal static void validate (PlaybackOptions options) throws Error {
            string device = options.audio_device_id;
            if (device == "" || device.length > 256 || !device.validate ()) {
                throw new MediaError.INVALID_ARGUMENT ("Invalid audio output device ID");
            }
            for (int index = 0; index < device.length; index++) {
                if (device[index] < 32 || device[index] == 127) {
                    throw new MediaError.INVALID_ARGUMENT ("Invalid control in audio device ID");
                }
            }
            if (((int) options.passthrough_codecs & ~CODEC_MASK) != 0) {
                throw new MediaError.INVALID_ARGUMENT ("Unknown audio passthrough codec mask");
            }
            if (options.audio_policy == AudioOutputPolicy.PREFER_PASSTHROUGH &&
                (device == "auto" || options.passthrough_codecs == AudioPassthroughCodec.NONE)) {
                throw new MediaError.UNSUPPORTED (
                    "Passthrough requires an explicit output device and receiver-approved codecs"
                );
            }
        }

        /** Maps an explicit channel layout preference to mpv's supported options. */
        internal static string pcm_channels_for_engine (PlaybackOptions options) {
            return options.pcm_channel_policy == PcmChannelPolicy.PRESERVE_SOURCE
                ? "auto" : "auto-safe";
        }

        /** Builds an mpv audio-spdif list from explicitly approved domain enum flags. */
        internal static string codecs_for_engine (PlaybackOptions options) {
            if (options.audio_policy != AudioOutputPolicy.PREFER_PASSTHROUGH) {
                return "";
            }
            string[] tokens = {};
            var requested = options.passthrough_codecs;
            if ((requested & AudioPassthroughCodec.AC3) != AudioPassthroughCodec.NONE) {
                tokens += "ac3";
            }
            if ((requested & AudioPassthroughCodec.EAC3) != AudioPassthroughCodec.NONE) {
                tokens += "eac3";
            }
            if ((requested & AudioPassthroughCodec.TRUEHD) != AudioPassthroughCodec.NONE) {
                tokens += "truehd";
            }
            if ((requested & AudioPassthroughCodec.DTS) != AudioPassthroughCodec.NONE) {
                tokens += "dts";
            }
            if ((requested & AudioPassthroughCodec.DTS_HD) != AudioPassthroughCodec.NONE) {
                tokens += "dts-hd";
            }
            return string.joinv (",", tokens);
        }
    }
}
