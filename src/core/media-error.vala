[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Identifies failures at the public media API boundary. */
    public errordomain MediaError {
        /** The request cannot be represented as a supported source. */
        INVALID_SOURCE,
        /** An operation has an invalid argument or state. */
        INVALID_ARGUMENT,
        /** A required playback or probe engine is not installed or implemented. */
        ENGINE_UNAVAILABLE,
        /** An installed backend cannot support the particular input or operation. */
        UNSUPPORTED,
        /** Opening, decoding, or rendering failed at runtime. */
        PLAYBACK_FAILED
    }
}
