[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Video stream metadata that does not assert a working output pipeline. */
    public sealed class VideoInformation : Object {
        /** Source codec identifier, or an empty string when unknown. */
        public string codec { get; construct; default = ""; }

        /** Coded frame width in pixels, zero if unknown. */
        public uint width_px { get; construct; default = 0; }

        /** Coded frame height in pixels, zero if unknown. */
        public uint height_px { get; construct; default = 0; }

        /** Decoded source bit depth, zero if unknown. */
        public uint bit_depth { get; construct; default = 0; }

        /** HDR signaling identified within the input stream. */
        public HdrFormat hdr_format { get; construct; default = HdrFormat.UNKNOWN; }

        /** Dolby Vision profile number, zero if not identified. */
        public uint dolby_vision_profile { get; construct; default = 0; }

        /** Constructs an unprobed descriptor with no assumed codec capabilities. */
        public VideoInformation () {
            Object ();
        }
    }
}
