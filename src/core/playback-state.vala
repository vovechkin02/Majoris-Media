[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Observed playback lifecycle; individual values are not codec guarantees. */
    public enum PlaybackState {
        /** No source is assigned. */
        EMPTY,
        /** An asynchronous source-open operation is pending. */
        OPENING,
        /** The selected source is ready for playback. */
        READY,
        /** Media is currently playing. */
        PLAYING,
        /** Playback is intentionally paused. */
        PAUSED,
        /** Playback stopped while retaining the source. */
        STOPPED,
        /** The source reached its natural end. */
        ENDED,
        /** Opening or playback failed; inspect the last error. */
        ERROR
    }

    /** Identifies where a media source is supplied from. */
    public enum SourceKind {
        /** A local GIO file. */
        LOCAL_FILE,
        /** An HTTP or HTTPS resource. */
        NETWORK
    }

    /** Categorizes individual stream tracks, independent of container type. */
    public enum TrackKind {
        /** A decoded or encoded video stream. */
        VIDEO,
        /** A decoded or encoded audio stream. */
        AUDIO,
        /** A text or bitmap subtitle stream. */
        SUBTITLE
    }

    /** Declares what has actually been established about an output capability. */
    public enum CapabilityStatus {
        /** No valid capability determination has yet been made. */
        UNKNOWN,
        /** Runtime probing confirmed that the capability is available. */
        AVAILABLE,
        /** Runtime probing confirmed that the capability is unavailable. */
        UNAVAILABLE,
        /** The feature may exist but has not been validated on this output. */
        UNVERIFIED
    }

    /** Reports the HDR source signaling without implying native HDR scanout. */
    public enum HdrFormat {
        /** Source metadata has not been probed. */
        UNKNOWN,
        /** SDR source with no HDR signaling. */
        SDR,
        /** Static HDR10 metadata. */
        HDR10,
        /** HDR10+ dynamic metadata. */
        HDR10_PLUS,
        /** Hybrid log-gamma transfer. */
        HLG,
        /** Dolby Vision profile-dependent metadata. */
        DOLBY_VISION
    }

    /** Describes the display path actually established for a source and output. */
    public enum HdrPresentation {
        /** Output presentation has not been validated. */
        UNVERIFIED,
        /** Source is processed for a standard-dynamic-range output. */
        TONE_MAPPED_SDR,
        /** Verified native extended-range display presentation. */
        NATIVE_HDR,
        /** This output cannot display the required video presentation. */
        UNSUPPORTED
    }

    /** Identifies the spatial-audio signaling found within a source. */
    public enum SpatialAudioFormat {
        /** The source has not been inspected or no conclusion was reached. */
        UNKNOWN,
        /** Channels rather than object-audio metadata have been established. */
        CHANNEL_BASED,
        /** Dolby Atmos metadata was identified. */
        DOLBY_ATMOS,
        /** DTS:X metadata was identified. */
        DTS_X
    }

    /** Selects the requested audio output policy, subject to device negotiation. */
    public enum AudioOutputPolicy {
        /** Negotiate a safe output path with the active device. */
        AUTO,
        /** Decode to PCM instead of requesting encoded passthrough. */
        DECODE_PCM,
        /** Prefer encoded passthrough only when the selected device supports it. */
        PREFER_PASSTHROUGH
    }

    /** Selects the desired HDR handling policy, not an output guarantee. */
    public enum HdrOutputPolicy {
        /** Prefer the highest verified appropriate output capability. */
        AUTO,
        /** Render HDR content as tone-mapped SDR. */
        TONE_MAP_SDR,
        /** Request native HDR only when verified by the display pipeline. */
        PREFER_NATIVE
    }
}
