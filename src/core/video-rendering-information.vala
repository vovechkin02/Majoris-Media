[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Renderer-local SDR framebuffer telemetry, not compositor or monitor validation. */
    public sealed class VideoRenderingInformation : Object {
        /** Actual embedded rendering API, empty before GL initialization. */
        public string backend { get; construct; default = ""; }

        /** Observed bound GL color attachment red-channel bit depth, zero if unknown. */
        public int red_bits { get; construct; default = 0; }

        /** Observed bound GL color attachment green-channel bit depth, zero if unknown. */
        public int green_bits { get; construct; default = 0; }

        /** Observed bound GL color attachment blue-channel bit depth, zero if unknown. */
        public int blue_bits { get; construct; default = 0; }

        /** Bit depth actually supplied to mpv's render call for dithering. */
        public int render_depth_bits { get; construct; default = 0; }

        /** True only after a host-supplied ICC profile was accepted by libmpv. */
        public bool icc_profile_active { get; construct; default = false; }

        /** True only after a successful render call into the GTK framebuffer. */
        public bool frame_submitted { get; construct; default = false; }

        /** Known SDR processing target; not proof of output-monitor color accuracy. */
        public HdrPresentation presentation {
            get;
            construct;
            default = HdrPresentation.UNVERIFIED;
        }

        /** Indicates whether all three framebuffer color channels are at least 10-bit. */
        public bool has_ten_bit_framebuffer {
            get {
                return red_bits >= 10 && green_bits >= 10 && blue_bits >= 10;
            }
        }

        /** Creates an unknown output snapshot before any actual rendering. */
        public VideoRenderingInformation () {
            Object ();
        }

        /** Parses renderer-local observations without inferring HDR scanout or Dolby Vision FEL. */
        public VideoRenderingInformation.from_metadata (Variant metadata) {
            Object (
                backend: read_string (metadata, "backend"),
                red_bits: read_int (metadata, "red-bits"),
                green_bits: read_int (metadata, "green-bits"),
                blue_bits: read_int (metadata, "blue-bits"),
                render_depth_bits: read_int (metadata, "render-depth-bits"),
                icc_profile_active: read_bool (metadata, "icc-active"),
                frame_submitted: read_bool (metadata, "frame-submitted"),
                presentation: read_bool (metadata, "frame-submitted") &&
                    read_string (metadata, "backend") == "libmpv-opengl"
                    ? HdrPresentation.TONE_MAPPED_SDR : HdrPresentation.UNVERIFIED
            );
        }

        /** Reads an optional string field from native a{sv} snapshots. */
        private static string read_string (Variant metadata, string key) {
            var field = metadata.lookup_value (key, new VariantType ("s"));
            return field != null ? field.get_string () : "";
        }

        /** Reads a nonnegative GL bit count while preserving an unknown zero. */
        private static int read_int (Variant metadata, string key) {
            var field = metadata.lookup_value (key, new VariantType ("i"));
            return field != null && field.get_int32 () > 0 ? field.get_int32 () : 0;
        }

        /** Reads an optional boolean without claiming unsupported capabilities. */
        private static bool read_bool (Variant metadata, string key) {
            var field = metadata.lookup_value (key, new VariantType ("b"));
            return field != null && field.get_boolean ();
        }

        /** Avoids notifying GTK consumers when the framebuffer telemetry is unchanged. */
        public bool equals_values (VideoRenderingInformation other) {
            return backend == other.backend && red_bits == other.red_bits &&
                green_bits == other.green_bits && blue_bits == other.blue_bits &&
                render_depth_bits == other.render_depth_bits &&
                icc_profile_active == other.icc_profile_active &&
                frame_submitted == other.frame_submitted && presentation == other.presentation;
        }
    }
}
