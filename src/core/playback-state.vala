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
        NETWORK,
        /** Standalone local MPEG transport stream, including M2TS; no disc dependency. */
        TRANSPORT_STREAM,
        /** A local DVD disc, directory, or explicitly identified DVD ISO image. */
        DVD_DISC,
        /** A local Blu-ray/UHD Blu-ray disc, directory, or identified ISO image. */
        BLURAY_DISC
    }

    /** Distinguishes optical disc format without trying to infer it from an ISO suffix. */
    public enum DiscKind {
        /** Not an optical disc source. */
        NONE,
        /** DVD-Video source. */
        DVD,
        /** Blu-ray or UHD Blu-ray source. */
        BLURAY
    }

    /** Determines which disc entry is requested at initial load. */
    public enum DiscStartMode {
        /** Choose the longest available title or playlist. */
        LONGEST,
        /** Choose the first available title. */
        FIRST,
        /** Enter the interactive menu when a suitable engine supports it. */
        MENU,
        /** Select an explicit zero-based title index. */
        TITLE,
        /** Open the specified five-digit Blu-ray MPLS playlist number. */
        PLAYLIST
    }

    /** Narrow set of validated optical-disc navigation commands. */
    public enum DiscMenuAction {
        /** Move menu focus upward. */
        UP,
        /** Move menu focus downward. */
        DOWN,
        /** Move menu focus left. */
        LEFT,
        /** Move menu focus right. */
        RIGHT,
        /** Activate the focused menu item. */
        SELECT,
        /** Return to the previous menu. */
        BACK,
        /** Navigate to a disc's top-level menu. */
        MENU
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

    /** Declares the embedded SDR target or experimental PQ texture encoding. */
    public enum ColorOutputTarget {
        /** Eight-bit SDR BT.709 primaries with a BT.1886 transfer curve. */
        SDR_BT709_BT1886,
        /** Opt-in BT.2020/PQ GL texture; compositor HDR is not guaranteed. */
        EXPERIMENTAL_BT2020_PQ
    }

    /** Restricts SDR tone mapping to algorithms available on legacy libmpv OpenGL. */
    public enum ToneMappingAlgorithm {
        /** Use the engine's stable automatic SDR curve. */
        AUTO,
        /** ITU-R BT.2390 perceptual EETF. */
        BT2390,
        /** Linear-segment Möbius roll-off. */
        MOBIUS,
        /** Hable filmic roll-off. */
        HABLE
    }

    /** Balances GPU work against visible banding on the embedded SDR path. */
    public enum VideoQualityPolicy {
        /** Preserve the normal GPU workload and default scaling. */
        BALANCED,
        /** Enable a bounded debanding pass for sufficiently fast devices. */
        HIGH_QUALITY
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

    /** Explicit encoded formats approved for one user-chosen output endpoint. */
    [Flags]
    public enum AudioPassthroughCodec {
        /** Never request compressed IEC 61937 output. */
        NONE = 0,
        /** Dolby Digital AC-3 transport. */
        AC3 = 1 << 0,
        /** Dolby Digital Plus E-AC-3 transport, possibly with Atmos metadata. */
        EAC3 = 1 << 1,
        /** Lossless Dolby TrueHD transport, possibly with Atmos metadata. */
        TRUEHD = 1 << 2,
        /** Core DTS compressed transport. */
        DTS = 1 << 3,
        /** DTS-HD high-resolution/master-audio transport, potentially containing DTS:X. */
        DTS_HD = 1 << 4
    }

    /** Local engine-observed audio path, not external receiver validation. */
    public enum AudioTransportState {
        /** No audio output format has yet been observed. */
        UNKNOWN,
        /** Decoder produces a non-IEC 61937 audio output format. */
        DECODED_PCM,
        /** libmpv reports an encoded IEC 61937 output format. */
        ENCODED_OBSERVED
    }

    /** Requested PCM channel layout behavior when the sound device accepts PCM. */
    public enum PcmChannelPolicy {
        /** Follow the safe system-preferred layout; may downmix to stereo. */
        SYSTEM_DEFAULT,
        /** Prefer the source layout; may be remixed if the endpoint rejects it. */
        PRESERVE_SOURCE
    }

    /** Selects the desired HDR handling policy, not an output guarantee. */
    public enum HdrOutputPolicy {
        /** Prefer the highest verified appropriate output capability. */
        AUTO,
        /** Render HDR content as tone-mapped SDR. */
        TONE_MAP_SDR,
        /** Request native HDR only when verified by the display pipeline. */
        PREFER_NATIVE,
        /** Request a color-tagged PQ framebuffer through a patched gpu-next renderer. */
        EXPERIMENTAL_PQ_TEXTURE
    }
}
