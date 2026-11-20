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
    return Test.run ();
}
