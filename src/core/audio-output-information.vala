[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Engine-reported audio output; no HDMI receiver handshake is implied. */
    public sealed class AudioOutputInformation : Object {
        /** Requested output device or auto for the system default. */
        public string device_id { get; construct; default = ""; }

        /** Selected mpv audio-output driver, empty until initialized. */
        public string driver { get; construct; default = ""; }

        /** Reported output sample format such as float or spdif-ac3. */
        public string sample_format { get; construct; default = ""; }

        /** Reported output channel arrangement, empty when unknown. */
        public string channel_layout { get; construct; default = ""; }

        /** Actual output channel count reported by the playback engine. */
        public uint channels { get; construct; default = 0; }

        /** Output sample rate, 0 if unknown or not applicable to a bitstream. */
        public uint sample_rate_hz { get; construct; default = 0; }

        /** Observed PCM or IEC 61937 path; not an Atmos/DTS:X receiver assertion. */
        public AudioTransportState transport { get; construct; default = AudioTransportState.UNKNOWN; }

        /** Creates a conservative output snapshot before device negotiation. */
        public AudioOutputInformation () {
            Object ();
        }

        /** Converts only type-checked native metadata to a public output descriptor. */
        public static AudioOutputInformation from_metadata (Variant data) {
            var format = read_text (data, "output-format");
            AudioTransportState state = AudioTransportState.UNKNOWN;
            if (format.has_prefix ("spdif-") || format.has_prefix ("iec61937")) {
                state = AudioTransportState.ENCODED_OBSERVED;
            } else if (format != "") {
                state = AudioTransportState.DECODED_PCM;
            }
            return new AudioOutputInformation.with_values (
                read_text (data, "device"), read_text (data, "driver"), format,
                read_text (data, "output-layout"), read_uint (data, "output-channels"),
                read_uint (data, "output-rate"), state
            );
        }

        /** Tests a stable value snapshot without depending on GObject identity. */
        public bool equals_values (AudioOutputInformation other) {
            return device_id == other.device_id && driver == other.driver &&
                sample_format == other.sample_format && channel_layout == other.channel_layout &&
                channels == other.channels && sample_rate_hz == other.sample_rate_hz &&
                transport == other.transport;
        }

        /** Constructs a fully described output snapshot from verified primitive fields. */
        private AudioOutputInformation.with_values (string device, string driver,
                string format, string layout, uint channels, uint rate,
                AudioTransportState transport) {
            Object (device_id: device, driver: driver, sample_format: format,
                    channel_layout: layout, channels: channels, sample_rate_hz: rate,
                    transport: transport);
        }

        /** Returns an empty string for unknown or ill-typed native metadata. */
        private static string read_text (Variant data, string key) {
            var value = data.lookup_value (key, new VariantType ("s"));
            return value == null ? "" : value.get_string ();
        }

        /** Bounds native numeric fields without guessing an unsupported device format. */
        private static uint read_uint (Variant data, string key) {
            var value = data.lookup_value (key, new VariantType ("x"));
            if (value == null) {
                return 0;
            }
            int64 number = value.get_int64 ();
            return number > 0 && number <= 1000000 ? (uint) number : 0;
        }
    }
}
