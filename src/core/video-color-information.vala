[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Identified stream color metadata; it does not certify HDR display output. */
    public sealed class VideoColorInformation : Object {
        /** Decoded input format classification, or UNKNOWN when unestablished. */
        public HdrFormat hdr_format { get; construct; default = HdrFormat.UNKNOWN; }

        /** Exact mpv source primaries token (such as bt.2020), if available. */
        public string primaries { get; construct; default = ""; }

        /** Exact mpv source transfer-function token, if available. */
        public string transfer { get; construct; default = ""; }

        /** Exact source matrix token, if available. */
        public string matrix { get; construct; default = ""; }

        /** Exact source encoding level/range token, if available. */
        public string color_levels { get; construct; default = ""; }

        /** Source MaxCLL in cd/m², zero when not present. */
        public double max_cll_nits { get; construct; default = 0.0; }

        /** Source MaxFALL in cd/m², zero when not present. */
        public double max_fall_nits { get; construct; default = 0.0; }

        /** Source mastering minimum luminance in cd/m², zero when unknown. */
        public double mastering_min_nits { get; construct; default = 0.0; }

        /** Source mastering maximum luminance in cd/m², zero when unknown. */
        public double mastering_max_nits { get; construct; default = 0.0; }

        /** Observed HDR10+ scene peak in cd/m², zero when not supplied. */
        public double scene_peak_nits { get; construct; default = 0.0; }

        /** Dolby Vision profile when identified by the engine; zero otherwise. */
        public uint dolby_vision_profile { get; construct; default = 0; }

        /** Whether this source is recognized as an HDR signaling format. */
        public bool is_hdr {
            get {
                return hdr_format != HdrFormat.UNKNOWN && hdr_format != HdrFormat.SDR;
            }
        }

        /** Constructs an unknown descriptor without guessing input colorimetry. */
        public VideoColorInformation () {
            Object ();
        }

        /** Classifies only validated typed backend metadata; missing fields stay unknown. */
        public static VideoColorInformation from_metadata (Variant metadata) {
            if (!metadata.is_of_type (new VariantType ("a{sv}"))) {
                return new VideoColorInformation ();
            }
            var primaries = read_string (metadata, "primaries");
            var transfer = read_string (metadata, "gamma");
            var matrix = read_string (metadata, "colormatrix");
            var levels = read_string (metadata, "colorlevels");
            var max_cll = read_number (metadata, "max-cll");
            var max_fall = read_number (metadata, "max-fall");
            var mastering_min = read_number (metadata, "min-luma");
            var mastering_max = read_number (metadata, "max-luma");
            var red = read_number (metadata, "scene-max-r");
            var green = read_number (metadata, "scene-max-g");
            var blue = read_number (metadata, "scene-max-b");
            double scene_peak = red;
            if (green > scene_peak) {
                scene_peak = green;
            }
            if (blue > scene_peak) {
                scene_peak = blue;
            }
            var dv_profile = read_number (metadata, "dolby-vision-profile");
            uint profile = 0;
            if (dv_profile >= 1 && dv_profile <= 32) {
                profile = (uint)dv_profile;
            }
            HdrFormat format = HdrFormat.UNKNOWN;
            if (profile != 0 || matrix == "dolbyvision") {
                format = HdrFormat.DOLBY_VISION;
            } else if (transfer == "hlg") {
                format = HdrFormat.HLG;
            } else if (transfer == "pq") {
                format = scene_peak > 0 ? HdrFormat.HDR10_PLUS : HdrFormat.HDR10;
            } else if (transfer != "" && transfer != "unknown") {
                format = HdrFormat.SDR;
            }
            return new VideoColorInformation.with_values (
                format, primaries, transfer, matrix, levels, max_cll, max_fall,
                mastering_min, mastering_max, scene_peak, profile
            );
        }

        /** Creates one coherent value snapshot; callers cannot mutate its fields. */
        private VideoColorInformation.with_values (HdrFormat format, string primaries,
                                                   string transfer, string matrix,
                                                   string levels, double max_cll,
                                                   double max_fall, double mastering_min,
                                                   double mastering_max, double scene_peak,
                                                   uint profile) {
            Object (
                hdr_format: format, primaries: primaries, transfer: transfer,
                matrix: matrix, color_levels: levels, max_cll_nits: max_cll,
                max_fall_nits: max_fall, mastering_min_nits: mastering_min,
                mastering_max_nits: mastering_max, scene_peak_nits: scene_peak,
                dolby_vision_profile: profile
            );
        }

        /** Compares value snapshots so repeated mpv events do not flood consumers. */
        internal bool equals_values (VideoColorInformation other) {
            return hdr_format == other.hdr_format && primaries == other.primaries &&
                transfer == other.transfer && matrix == other.matrix &&
                color_levels == other.color_levels && max_cll_nits == other.max_cll_nits &&
                max_fall_nits == other.max_fall_nits &&
                mastering_min_nits == other.mastering_min_nits &&
                mastering_max_nits == other.mastering_max_nits &&
                scene_peak_nits == other.scene_peak_nits &&
                dolby_vision_profile == other.dolby_vision_profile;
        }

        /** Reads only a string value from the known metadata variant dictionary. */
        private static string read_string (Variant data, string key) {
            var value = data.lookup_value (key, new VariantType ("s"));
            return value == null ? "" : value.get_string ();
        }

        /** Reads numeric metadata without converting NaN, negative, or absent values. */
        private static double read_number (Variant data, string key) {
            var value = data.lookup_value (key, null);
            if (value == null) {
                return 0.0;
            }
            double number = 0.0;
            if (value.is_of_type (new VariantType ("d"))) {
                number = value.get_double ();
            } else if (value.is_of_type (new VariantType ("x"))) {
                number = (double)value.get_int64 ();
            } else if (value.is_of_type (new VariantType ("u"))) {
                number = (double)value.get_uint32 ();
            }
            if (number < 0.0 || number > 100000.0 || number != number) {
                return 0.0;
            }
            return number;
        }
    }
}
