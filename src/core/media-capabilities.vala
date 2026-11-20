[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Snapshot of independently validated engine, display, and audio capabilities. */
    public sealed class MediaCapabilities : Object {
        /** Whether an operational playback backend was established. */
        public CapabilityStatus playback_engine { get; construct; }

        /** Availability of an operational video decoder for this session. */
        public CapabilityStatus video_decoding { get; construct; }

        /** Availability of verified native HDR monitor presentation. */
        public CapabilityStatus native_hdr { get; construct; }

        /** Availability of encoded audio output on the selected device. */
        public CapabilityStatus encoded_audio { get; construct; }

        /** Verified HDR presentation path, independent of source metadata. */
        public HdrPresentation hdr_presentation { get; construct; }

        /** Embedded gpu-next compiled support, not proof of actual GL initialization. */
        public CapabilityStatus embedded_gpu_next { get; construct; }

        /** No validated full Profile 7 FEL reconstruction exists for this GTK renderer. */
        public CapabilityStatus dolby_vision_fel { get; construct; }

        /** Creates a conservative snapshot without claiming untested output support. */
        public MediaCapabilities (CapabilityStatus playback_engine = CapabilityStatus.UNKNOWN,
                                  CapabilityStatus embedded_backend = CapabilityStatus.UNAVAILABLE) {
            Object (
                playback_engine: playback_engine,
                video_decoding: CapabilityStatus.UNKNOWN,
                native_hdr: CapabilityStatus.UNVERIFIED,
                encoded_audio: CapabilityStatus.UNVERIFIED,
                hdr_presentation: HdrPresentation.UNVERIFIED,
                embedded_gpu_next: embedded_backend,
                dolby_vision_fel: CapabilityStatus.UNVERIFIED
            );
        }
    }
}
