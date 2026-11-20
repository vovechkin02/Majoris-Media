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

/** Registers small, deterministic public Core API checks. */
int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/media/core/source", test_source_contract);
    Test.add_func ("/media/core/source-rejection", test_source_rejection);
    Test.add_func ("/media/core/initial", test_session_contract);
    Test.add_func ("/media/core/stage3-empty-models", test_stage3_empty_models);
    Test.add_func ("/media/core/missing-file", test_open_failure);
    Test.add_func ("/media/core/pre-canceled", test_canceled_open);
    return Test.run ();
}
