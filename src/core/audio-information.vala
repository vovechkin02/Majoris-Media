[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Source stream audio metadata, not the negotiated output signal. */
    public sealed class AudioInformation : Object {
        /** Stream codec token, or an empty string when unknown. */
        public string codec { get; construct; default = ""; }

        /** Original stream sample rate in hertz, zero when unknown. */
        public uint sample_rate_hz { get; construct; default = 0; }

        /** Number of source channels, zero when unknown. */
        public uint channels { get; construct; default = 0; }

        /** Source channel layout reported by the engine, or empty. */
        public string channel_layout { get; construct; default = ""; }

        /** Decoded source PCM format, or empty before probing. */
        public string sample_format { get; construct; default = ""; }

        /** Atmos/DTS:X only when independently identified, never inferred from codec. */
        public SpatialAudioFormat spatial_format {
            get;
            construct;
            default = SpatialAudioFormat.UNKNOWN;
        }

        /** Constructs unknown source metadata. */
        public AudioInformation () {
            Object ();
        }

        /** Creates a conservative snapshot from native stream and decoder metadata. */
        public static AudioInformation from_metadata (Variant data) {
            var codec_value = data.lookup_value ("source-codec", new VariantType ("s"));
            var format_value = data.lookup_value ("source-format", new VariantType ("s"));
            var layout_value = data.lookup_value ("source-layout", new VariantType ("s"));
            var channels_value = data.lookup_value ("source-channels", new VariantType ("x"));
            var rate_value = data.lookup_value ("source-rate", new VariantType ("x"));
            int64 channel_count = channels_value == null ? 0 : channels_value.get_int64 ();
            int64 rate_hz = rate_value == null ? 0 : rate_value.get_int64 ();
            return new AudioInformation.with_values (
                codec_value == null ? "" : codec_value.get_string (),
                rate_hz > 0 && rate_hz <= 1000000 ? (uint) rate_hz : 0,
                channel_count > 0 && channel_count <= 256 ? (uint) channel_count : 0,
                layout_value == null ? "" : layout_value.get_string (),
                format_value == null ? "" : format_value.get_string ()
            );
        }

        /** Compares immutable audio descriptors for meaningful change notifications. */
        public bool equals_values (AudioInformation other) {
            return codec == other.codec && sample_rate_hz == other.sample_rate_hz &&
                channels == other.channels && channel_layout == other.channel_layout &&
                sample_format == other.sample_format && spatial_format == other.spatial_format;
        }

        /** Constructs only source-level attributes which the decoder reported. */
        private AudioInformation.with_values (string codec, uint rate, uint channels,
                string layout, string format) {
            Object (codec: codec, sample_rate_hz: rate, channels: channels,
                    channel_layout: layout, sample_format: format,
                    spatial_format: SpatialAudioFormat.UNKNOWN);
        }
    }
}
