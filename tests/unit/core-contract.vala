/** Ensures local and network sources preserve URI identity without doing I/O. */
private void test_source_contract () {
    try {
        var local = new MediaKit.MediaSource.for_path ("/tmp/sample.mkv");
        assert (local.kind == MediaKit.SourceKind.LOCAL_FILE);
        assert (local.uri.has_prefix ("file:"));
        var network = new MediaKit.MediaSource.for_uri ("https://example.org/video.mp4");
        assert (network.kind == MediaKit.SourceKind.NETWORK);
        assert (network.uri.has_prefix ("https:"));
    } catch (Error error) {
        assert_not_reached ();
    }
}

/** Rejects unsupported protocols before any backend interaction. */
private void test_source_rejection () {
    bool rejected = false;
    try {
        var source = new MediaKit.MediaSource.for_uri ("ftp://example.org/file");
        assert (source.kind != MediaKit.SourceKind.NETWORK);
    } catch (Error error) {
        rejected = true;
    }
    assert (rejected);
}

/** Initial sessions do not pretend to have successfully opened a stream. */
private void test_session_contract () {
    var session = new MediaKit.MediaSession ();
    assert (session.state == MediaKit.PlaybackState.EMPTY);
    assert (session.capabilities.native_hdr == MediaKit.CapabilityStatus.UNVERIFIED);
    assert (session.capabilities.encoded_audio == MediaKit.CapabilityStatus.UNVERIFIED);
    assert (session.duration_us == 0);
    bool refused = false;
    try {
        session.play ();
    } catch (Error error) {
        refused = true;
    }
    assert (refused);
    assert (session.state == MediaKit.PlaybackState.EMPTY);
}

/** Empty sessions expose stable read-only models and reject premature controls. */
private void test_stage3_empty_models () {
    var session = new MediaKit.MediaSession ();
    assert (session.tracks.get_n_items () == 0);
    assert (session.chapters.get_n_items () == 0);
    assert (session.current_chapter_index == -1);
    assert (session.buffering_percent == -1);
    assert (!session.is_buffering);
    assert (session.subtitles_visible);
    assert (session.active_video_decoder == "");
    assert (!session.hardware_decoding_active);
    bool rejected = false;
    try {
        session.select_audio_track ("1");
    } catch (MediaKit.MediaError.INVALID_ARGUMENT error) {
        rejected = true;
    } catch (Error error) {
        assert_not_reached ();
    }
    assert (rejected);
    rejected = false;
    try {
        session.select_chapter (0);
    } catch (MediaKit.MediaError.INVALID_ARGUMENT error) {
        rejected = true;
    } catch (Error error) {
        assert_not_reached ();
    }
    assert (rejected);
    session.close ();
    assert (session.tracks.get_n_items () == 0);
    assert (session.chapters.get_n_items () == 0);
}

/** Missing files report a real error even with a functional native engine. */
private void test_open_failure () {
    var loop = new MainLoop ();
    var session = new MediaKit.MediaSession ();
    bool rejected = false;
    uint timeout_id = 0;
    timeout_id = Timeout.add_seconds (10, () => {
        timeout_id = 0;
        loop.quit ();
        return Source.REMOVE;
    });
    try {
        var source = new MediaKit.MediaSource.for_path (
            "/tmp/majoris-media-definitely-absent-stage2-sample.mkv"
        );
        session.open_async.begin (source, null, (object, result) => {
            try {
                session.open_async.end (result);
            } catch (Error error) {
                rejected = true;
            }
            session.close ();
            loop.quit ();
        });
        loop.run ();
    } catch (Error error) {
        assert_not_reached ();
    }
    if (timeout_id != 0) {
        Source.remove (timeout_id);
    }
    assert (rejected);
    assert (session.state == MediaKit.PlaybackState.EMPTY);
}

/** A pre-canceled request must not allocate or open any source. */
private void test_canceled_open () {
    var loop = new MainLoop ();
    var session = new MediaKit.MediaSession ();
    var cancellation = new Cancellable ();
    cancellation.cancel ();
    try {
        var source = new MediaKit.MediaSource.for_path ("/tmp/sample.mp4");
        Idle.add (() => {
            session.open_async.begin (source, cancellation, (object, result) => {
                bool rejected = false;
                try {
                    session.open_async.end (result);
                } catch (IOError.CANCELLED error) {
                    rejected = true;
                } catch (Error error) {
                    assert_not_reached ();
                }
                assert (rejected);
                assert (session.state == MediaKit.PlaybackState.EMPTY);
                loop.quit ();
            });
            return Source.REMOVE;
        });
        loop.run ();
    } catch (Error error) {
        assert_not_reached ();
    }
}

/** Validates source-only HDR classification without any media decoder or GPU. */
private void test_stage4_color_classification () {
    var empty = new VariantBuilder (new VariantType ("a{sv}"));
    var unknown = MediaKit.VideoColorInformation.from_metadata (empty.end ());
    assert (unknown.hdr_format == MediaKit.HdrFormat.UNKNOWN);
    assert (!unknown.is_hdr);

    var sdr_fields = new VariantBuilder (new VariantType ("a{sv}"));
    sdr_fields.add ("{sv}", "gamma", new Variant.string ("bt.1886"));
    sdr_fields.add ("{sv}", "primaries", new Variant.string ("bt.709"));
    var sdr = MediaKit.VideoColorInformation.from_metadata (sdr_fields.end ());
    assert (sdr.hdr_format == MediaKit.HdrFormat.SDR);
    assert (!sdr.is_hdr);

    var hdr_fields = new VariantBuilder (new VariantType ("a{sv}"));
    hdr_fields.add ("{sv}", "gamma", new Variant.string ("pq"));
    hdr_fields.add ("{sv}", "primaries", new Variant.string ("bt.2020"));
    hdr_fields.add ("{sv}", "max-cll", new Variant.double (1000.0));
    var hdr = MediaKit.VideoColorInformation.from_metadata (hdr_fields.end ());
    assert (hdr.hdr_format == MediaKit.HdrFormat.HDR10);
    assert (hdr.max_cll_nits == 1000.0);
    assert (hdr.is_hdr);

    var ambiguous_fields = new VariantBuilder (new VariantType ("a{sv}"));
    ambiguous_fields.add ("{sv}", "primaries", new Variant.string ("bt.2020"));
    var ambiguous = MediaKit.VideoColorInformation.from_metadata (
        ambiguous_fields.end ()
    );
    assert (ambiguous.hdr_format == MediaKit.HdrFormat.UNKNOWN);

    var dynamic_fields = new VariantBuilder (new VariantType ("a{sv}"));
    dynamic_fields.add ("{sv}", "gamma", new Variant.string ("pq"));
    dynamic_fields.add ("{sv}", "scene-max-r", new Variant.double (1100.0));
    dynamic_fields.add ("{sv}", "scene-max-g", new Variant.double (900.0));
    var dynamic = MediaKit.VideoColorInformation.from_metadata (dynamic_fields.end ());
    assert (dynamic.hdr_format == MediaKit.HdrFormat.HDR10_PLUS);
    assert (dynamic.scene_peak_nits == 1100.0);

    var hlg_fields = new VariantBuilder (new VariantType ("a{sv}"));
    hlg_fields.add ("{sv}", "gamma", new Variant.string ("hlg"));
    var hlg = MediaKit.VideoColorInformation.from_metadata (hlg_fields.end ());
    assert (hlg.hdr_format == MediaKit.HdrFormat.HLG);

    var dv_fields = new VariantBuilder (new VariantType ("a{sv}"));
    dv_fields.add ("{sv}", "gamma", new Variant.string ("pq"));
    dv_fields.add ("{sv}", "dolby-vision-profile", new Variant.int64 (7));
    var dv = MediaKit.VideoColorInformation.from_metadata (dv_fields.end ());
    assert (dv.hdr_format == MediaKit.HdrFormat.DOLBY_VISION);
    assert (dv.dolby_vision_profile == 7);

    var session = new MediaKit.MediaSession ();
    assert (session.video_color.hdr_format == MediaKit.HdrFormat.UNKNOWN);
    assert (session.color_output_target == MediaKit.ColorOutputTarget.SDR_BT709_BT1886);
    assert (session.capabilities.native_hdr == MediaKit.CapabilityStatus.UNVERIFIED);
}

/** Rejects a forced native-HDR policy before changing an unopened session. */
private void test_stage4_native_hdr_policy () {
    var options = new MediaKit.PlaybackOptions ();
    options.hdr_policy = MediaKit.HdrOutputPolicy.PREFER_NATIVE;
    var session = new MediaKit.MediaSession (options);
    var loop = new MainLoop ();
    try {
        var source = new MediaKit.MediaSource.for_path ("/tmp/hdr-sample.mkv");
        Idle.add (() => {
            session.open_async.begin (source, null, (object, result) => {
                bool unsupported = false;
                try {
                    session.open_async.end (result);
                } catch (MediaKit.MediaError.UNSUPPORTED error) {
                    unsupported = true;
                } catch (Error error) {
                    assert_not_reached ();
                }
                assert (unsupported);
                assert (session.source == null);
                assert (session.state == MediaKit.PlaybackState.EMPTY);
                loop.quit ();
            });
            return Source.REMOVE;
        });
        loop.run ();
    } catch (Error error) {
        assert_not_reached ();
    }
}

/** Audio source and output are separate and do not imply external spatial rendering. */
private void test_stage5_audio_metadata () {
    var native = new VariantBuilder (new VariantType ("a{sv}"));
    native.add ("{sv}", "source-codec", new Variant.string ("truehd"));
    native.add ("{sv}", "source-rate", new Variant.int64 (48000));
    native.add ("{sv}", "source-channels", new Variant.int64 (8));
    native.add ("{sv}", "source-layout", new Variant.string ("7.1"));
    native.add ("{sv}", "output-format", new Variant.string ("spdif-truehd"));
    native.add ("{sv}", "output-rate", new Variant.int64 (192000));
    native.add ("{sv}", "output-channels", new Variant.int64 (2));
    native.add ("{sv}", "device", new Variant.string ("alsa/hdmi:CARD=Example,DEV=0"));
    native.add ("{sv}", "driver", new Variant.string ("alsa"));
    var metadata = native.end ();
    var audio = MediaKit.AudioInformation.from_metadata (metadata);
    var output = MediaKit.AudioOutputInformation.from_metadata (metadata);
    assert (audio.codec == "truehd");
    assert (audio.channels == 8);
    assert (audio.sample_rate_hz == 48000);
    assert (audio.spatial_format == MediaKit.SpatialAudioFormat.UNKNOWN);
    assert (output.sample_format == "spdif-truehd");
    assert (output.transport == MediaKit.AudioTransportState.ENCODED_OBSERVED);
    assert (output.channels == 2);
    assert (output.device_id.has_prefix ("alsa/"));
    var empty = new VariantBuilder (new VariantType ("a{sv}"));
    var unknown = MediaKit.AudioOutputInformation.from_metadata (empty.end ());
    assert (unknown.transport == MediaKit.AudioTransportState.UNKNOWN);
    assert (unknown.driver == "");
    var pcm = new VariantBuilder (new VariantType ("a{sv}"));
    pcm.add ("{sv}", "output-format", new Variant.string ("float"));
    var decoded = MediaKit.AudioOutputInformation.from_metadata (pcm.end ());
    assert (decoded.transport == MediaKit.AudioTransportState.DECODED_PCM);
    assert (!decoded.equals_values (output));
}

/** The empty session cannot enumerate or pretend to choose a physical sink. */
private void test_stage5_empty_audio () {
    var session = new MediaKit.MediaSession ();
    assert (session.audio_devices.get_n_items () == 0);
    assert (session.source_audio.channels == 0);
    assert (session.audio_output.transport == MediaKit.AudioTransportState.UNKNOWN);
    assert (session.capabilities.encoded_audio == MediaKit.CapabilityStatus.UNVERIFIED);
    bool invalid = false;
    try {
        session.select_audio_device ("auto");
    } catch (MediaKit.MediaError.INVALID_ARGUMENT error) {
        invalid = true;
    } catch (Error error) {
        assert_not_reached ();
    }
    assert (invalid);
}

/** Passthrough must be receiver-approved and bound to a named physical endpoint. */
private void test_stage5_passthrough_preflight () {
    var options = new MediaKit.PlaybackOptions ();
    assert (options.audio_policy == MediaKit.AudioOutputPolicy.AUTO);
    assert (options.pcm_channel_policy == MediaKit.PcmChannelPolicy.SYSTEM_DEFAULT);
    assert (options.passthrough_codecs == MediaKit.AudioPassthroughCodec.NONE);
    options.audio_policy = MediaKit.AudioOutputPolicy.PREFER_PASSTHROUGH;
    options.passthrough_codecs = MediaKit.AudioPassthroughCodec.AC3 |
        MediaKit.AudioPassthroughCodec.EAC3;
    var session = new MediaKit.MediaSession (options);
    var loop = new MainLoop ();
    try {
        var source = new MediaKit.MediaSource.for_path ("/tmp/example-surround.mkv");
        Idle.add (() => {
            session.open_async.begin (source, null, (object, result) => {
                bool rejected = false;
                try {
                    session.open_async.end (result);
                } catch (MediaKit.MediaError.UNSUPPORTED error) {
                    rejected = true;
                } catch (Error error) {
                    assert_not_reached ();
                }
                assert (rejected);
                assert (session.state == MediaKit.PlaybackState.EMPTY);
                assert (session.source == null);
                loop.quit ();
            });
            return Source.REMOVE;
        });
        loop.run ();
    } catch (Error error) {
        assert_not_reached ();
    }
}

/** Disc sources retain local identity while rejecting invalid title/playlist modes. */
private void test_stage6_disc_source_contract () {
    try {
        var dvd = new MediaKit.MediaSource.for_disc (
            "/dev/sr0", MediaKit.DiscKind.DVD
        );
        assert (dvd.is_disc);
        assert (dvd.kind == MediaKit.SourceKind.DVD_DISC);
        assert (dvd.disc_start == MediaKit.DiscStartMode.LONGEST);
        assert (dvd.uri.has_prefix ("file:"));
        var bluray = new MediaKit.MediaSource.for_disc (
            "/tmp/disc-image.iso", MediaKit.DiscKind.BLURAY,
            MediaKit.DiscStartMode.PLAYLIST, 800
        );
        assert (bluray.kind == MediaKit.SourceKind.BLURAY_DISC);
        assert (bluray.disc_selection == 800);
        assert (bluray.is_disc);
        var m2ts = new MediaKit.MediaSource.for_transport_stream (
            "/tmp/demo.m2ts"
        );
        assert (!m2ts.is_disc);
        assert (m2ts.kind == MediaKit.SourceKind.TRANSPORT_STREAM);
        assert (m2ts.uri.has_prefix ("file:"));
    } catch (Error error) {
        assert_not_reached ();
    }

    bool rejected = false;
    try {
        var invalid = new MediaKit.MediaSource.for_disc (
            "/dev/sr0", MediaKit.DiscKind.DVD,
            MediaKit.DiscStartMode.PLAYLIST, 25
        );
        assert (invalid.disc_kind == MediaKit.DiscKind.DVD);
    } catch (MediaKit.MediaError.INVALID_ARGUMENT error) {
        rejected = true;
    } catch (Error error) {
        assert_not_reached ();
    }
    assert (rejected);

    rejected = false;
    try {
        var invalid = new MediaKit.MediaSource.for_disc (
            "/dev/sr0", MediaKit.DiscKind.BLURAY,
            MediaKit.DiscStartMode.PLAYLIST, 100000
        );
        assert (invalid.disc_selection > 0);
    } catch (MediaKit.MediaError.INVALID_ARGUMENT error) {
        rejected = true;
    } catch (Error error) {
        assert_not_reached ();
    }
    assert (rejected);

    rejected = false;
    try {
        var invalid = new MediaKit.MediaSource.for_disc (
            "relative/path.iso", MediaKit.DiscKind.BLURAY
        );
        assert (invalid.is_disc);
    } catch (MediaKit.MediaError.INVALID_SOURCE error) {
        rejected = true;
    } catch (Error error) {
        assert_not_reached ();
    }
    assert (rejected);
}

/** Empty sessions never advertise optical-disc metadata or navigation capability. */
private void test_stage6_empty_disc_session () {
    var session = new MediaKit.MediaSession ();
    assert (session.disc_titles.get_n_items () == 0);
    assert (!session.disc_menu_supported);
    assert (!session.disc_menu_active);
    bool rejected = false;
    try {
        session.navigate_disc_menu (MediaKit.DiscMenuAction.MENU);
    } catch (MediaKit.MediaError.INVALID_ARGUMENT error) {
        rejected = true;
    } catch (Error error) {
        assert_not_reached ();
    }
    assert (rejected);
    session.close ();
    assert (session.disc_titles.get_n_items () == 0);
}

/** Distinguishes framebuffer bit depth and submitted SDR frames from real HDR output. */
private void test_stage7_renderer_metadata () {
    var unknown = new MediaKit.VideoRenderingInformation ();
    assert (unknown.backend == "");
    assert (unknown.render_depth_bits == 0);
    assert (!unknown.has_ten_bit_framebuffer);
    assert (unknown.presentation == MediaKit.HdrPresentation.UNVERIFIED);

    var data = new VariantBuilder (new VariantType ("a{sv}"));
    data.add ("{sv}", "backend", new Variant.string ("libmpv-opengl"));
    data.add ("{sv}", "red-bits", new Variant.int32 (10));
    data.add ("{sv}", "green-bits", new Variant.int32 (10));
    data.add ("{sv}", "blue-bits", new Variant.int32 (10));
    data.add ("{sv}", "render-depth-bits", new Variant.int32 (10));
    data.add ("{sv}", "icc-active", new Variant.boolean (true));
    data.add ("{sv}", "frame-submitted", new Variant.boolean (true));
    var result = new MediaKit.VideoRenderingInformation.from_metadata (data.end ());
    assert (result.backend == "libmpv-opengl");
    assert (result.has_ten_bit_framebuffer);
    assert (result.render_depth_bits == 10);
    assert (result.icc_profile_active);
    assert (result.frame_submitted);
    assert (result.presentation == MediaKit.HdrPresentation.TONE_MAPPED_SDR);
    assert (!unknown.equals_values (result));

    var malformed = new VariantBuilder (new VariantType ("a{sv}"));
    malformed.add ("{sv}", "red-bits", new Variant.int32 (-4));
    malformed.add ("{sv}", "blue-bits", new Variant.string ("12"));
    var safe = new MediaKit.VideoRenderingInformation.from_metadata (malformed.end ());
    assert (safe.red_bits == 0 && safe.blue_bits == 0);
    assert (!safe.has_ten_bit_framebuffer);
    assert (safe.presentation == MediaKit.HdrPresentation.UNVERIFIED);
}

/** Keeps Stage 7 user policies independent of actual hardware HDR capabilities. */
private void test_stage7_video_policies () {
    var options = new MediaKit.PlaybackOptions ();
    assert (options.tone_mapping == MediaKit.ToneMappingAlgorithm.AUTO);
    assert (options.video_quality == MediaKit.VideoQualityPolicy.BALANCED);
    options.tone_mapping = MediaKit.ToneMappingAlgorithm.BT2390;
    options.video_quality = MediaKit.VideoQualityPolicy.HIGH_QUALITY;
    assert (options.tone_mapping == MediaKit.ToneMappingAlgorithm.BT2390);
    assert (options.video_quality == MediaKit.VideoQualityPolicy.HIGH_QUALITY);
    var session = new MediaKit.MediaSession (options);
    assert (session.capabilities.embedded_gpu_next == MediaKit.CapabilityStatus.UNAVAILABLE);
    assert (session.capabilities.dolby_vision_fel == MediaKit.CapabilityStatus.UNVERIFIED);
    assert (session.capabilities.native_hdr != MediaKit.CapabilityStatus.AVAILABLE);
    assert (session.color_output_target == MediaKit.ColorOutputTarget.SDR_BT709_BT1886);
}

/** A candidate gpu-next renderer must never imply a verified Wayland HDR display. */
private void test_stage7_gpu_next_capabilities () {
    var candidate = new MediaKit.GpuNextCapabilities.from_probe (
        "/usr/bin/mpv", "mpv 0.42.0\n Copyright ...", true
    );
    assert (candidate.can_launch);
    assert (candidate.native_hdr == MediaKit.CapabilityStatus.UNVERIFIED);
    assert (candidate.dolby_vision_fel == MediaKit.CapabilityStatus.UNVERIFIED);
    assert (candidate.embedded_gpu_next == MediaKit.CapabilityStatus.UNAVAILABLE);
    assert (candidate.hdr10_plus_metadata_output == MediaKit.CapabilityStatus.UNAVAILABLE);

    var legacy = new MediaKit.GpuNextCapabilities.from_probe (
        "/usr/bin/mpv", "mpv 0.40.0", true
    );
    assert (!legacy.can_launch);
    assert (legacy.native_hdr == MediaKit.CapabilityStatus.UNAVAILABLE);
    var no_wayland = new MediaKit.GpuNextCapabilities.from_probe (
        "/usr/bin/mpv", "mpv v0.42.0", false
    );
    assert (!no_wayland.can_launch);
    var malformed = new MediaKit.GpuNextCapabilities.from_probe (
        "/usr/bin/mpv", "not an mpv version", true
    );
    assert (!malformed.can_launch);
    var empty = new MediaKit.GpuNextCapabilities ();
    assert (!empty.can_launch);
}

/** Advanced video arguments must be fixed, non-shell, and never reinterpret source paths. */
private void test_stage7_gpu_next_arguments () {
    var options = new MediaKit.GpuNextLaunchOptions ();
    try {
        var source = new MediaKit.MediaSource.for_path ("/tmp/--suspicious.mkv");
        var args = options.build_arguments ("/usr/bin/mpv", source);
        assert (args[0] == "/usr/bin/mpv");
        assert (args[2] == "--vo=gpu-next");
        assert (args[args.length - 2] == "--");
        assert (args[args.length - 1] == "/tmp/--suspicious.mkv");
        options.color_hint_mode = MediaKit.GpuNextColorHintMode.SOURCE_DYNAMIC;
        args = options.build_arguments ("/usr/bin/mpv", source);
        assert (args[7] == "--target-colorspace-hint-mode=source-dynamic");
        assert (args[4] == "--tone-mapping=auto");
        options.tone_mapping = MediaKit.GpuNextToneMapping.HDR10_PLUS;
        args = options.build_arguments ("/usr/bin/mpv", source);
        assert (args[4] == "--tone-mapping=st2094-40");
        options.tone_mapping = MediaKit.GpuNextToneMapping.DOLBY_VISION;
        args = options.build_arguments ("/usr/bin/mpv", source);
        assert (args[4] == "--tone-mapping=st2094-10");
    } catch (Error error) {
        assert_not_reached ();
    }

    bool rejected = false;
    try {
        var network = new MediaKit.MediaSource.for_uri ("https://example.org/media.mp4");
        options.build_arguments ("/usr/bin/mpv", network);
    } catch (MediaKit.MediaError.INVALID_SOURCE error) {
        rejected = true;
    } catch (Error error) {
        assert_not_reached ();
    }
    assert (rejected);
    options.allow_network = true;
    try {
        var network = new MediaKit.MediaSource.for_uri ("https://example.org/media.mp4");
        var args = options.build_arguments ("/usr/bin/mpv", network);
        assert (args[args.length - 1] == "https://example.org/media.mp4");
    } catch (Error error) {
        assert_not_reached ();
    }

    rejected = false;
    try {
        var disc = new MediaKit.MediaSource.for_disc (
            "/dev/sr0", MediaKit.DiscKind.BLURAY
        );
        options.build_arguments ("/usr/bin/mpv", disc);
    } catch (MediaKit.MediaError.UNSUPPORTED error) {
        rejected = true;
    } catch (Error error) {
        assert_not_reached ();
    }
    assert (rejected);

    var status = new MediaKit.GpuNextPlaybackStatus (
        true, 1000000, "gpu-next", "bt.2020", "pq"
    );
    assert (status.paused && status.position_us == 1000000);
    assert (status.native_hdr != MediaKit.CapabilityStatus.AVAILABLE);
    var playback = new MediaKit.GpuNextWindow ();
    assert (!playback.running && !playback.ready);
    playback.close ();
}

/** Registers small, deterministic public Core API checks. */
int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/media/core/source", test_source_contract);
    Test.add_func ("/media/core/source-rejection", test_source_rejection);
    Test.add_func ("/media/core/initial", test_session_contract);
    Test.add_func ("/media/core/stage3-empty-models", test_stage3_empty_models);
    Test.add_func ("/media/core/missing-file", test_open_failure);
    Test.add_func ("/media/core/pre-canceled", test_canceled_open);
    Test.add_func ("/media/core/stage4-color", test_stage4_color_classification);
    Test.add_func ("/media/core/stage4-native-hdr-policy", test_stage4_native_hdr_policy);
    Test.add_func ("/media/core/stage5-audio-metadata", test_stage5_audio_metadata);
    Test.add_func ("/media/core/stage5-empty-audio", test_stage5_empty_audio);
    Test.add_func ("/media/core/stage5-passthrough-preflight", test_stage5_passthrough_preflight);
    Test.add_func ("/media/core/stage6-disc-sources", test_stage6_disc_source_contract);
    Test.add_func ("/media/core/stage6-disc-session", test_stage6_empty_disc_session);
    Test.add_func ("/media/core/stage7-rendering-metadata", test_stage7_renderer_metadata);
    Test.add_func ("/media/core/stage7-rendering-policy", test_stage7_video_policies);
    Test.add_func ("/media/core/stage7-gpu-next-candidate", test_stage7_gpu_next_capabilities);
    Test.add_func ("/media/core/stage7-gpu-next-arguments", test_stage7_gpu_next_arguments);
    return Test.run ();
}
