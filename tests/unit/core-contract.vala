/** Checks that source construction establishes no unsupported decoding claims. */
private void test_source_contract () {
    try {
        var local_source = new MediaKit.MediaSource.for_path ("/tmp/sample.mkv");
        assert (local_source.kind == MediaKit.SourceKind.LOCAL_FILE);
        assert (local_source.uri.has_prefix ("file:"));

        var network_source = new MediaKit.MediaSource.for_uri ("https://example.org/video.mp4");
        assert (network_source.kind == MediaKit.SourceKind.NETWORK);
        assert (network_source.uri.has_prefix ("https:"));
    } catch (Error error) {
        assert_not_reached ();
    }
}

/** Ensures unsupported and ambiguous input schemes do not escape validation. */
private void test_source_rejection () {
    bool rejected = false;
    try {
        var source = new MediaKit.MediaSource.for_uri ("ftp://example.org/video.avi");
        assert (source.kind != MediaKit.SourceKind.NETWORK);
    } catch (Error error) {
        rejected = true;
    }
    assert (rejected);
}

/** Verifies Stage 1 never advertises a decoder or falsely enters PLAYING. */
private void test_unavailable_contract () {
    var session = new MediaKit.MediaSession ();
    assert (session.state == MediaKit.PlaybackState.EMPTY);
    assert (session.capabilities.playback_engine == MediaKit.CapabilityStatus.UNAVAILABLE);
    assert (session.capabilities.native_hdr == MediaKit.CapabilityStatus.UNVERIFIED);
    assert (session.capabilities.encoded_audio == MediaKit.CapabilityStatus.UNVERIFIED);

    bool refused = false;
    try {
        session.play ();
    } catch (Error error) {
        refused = true;
    }
    assert (refused);
    assert (session.state == MediaKit.PlaybackState.EMPTY);
}

/** Ensures a failure remains visible until close clears the session. */
private void test_open_failure () {
    var loop = new MainLoop ();
    var session = new MediaKit.MediaSession ();
    try {
        var source = new MediaKit.MediaSource.for_path ("/tmp/stage1-not-present.mkv");
        session.open_async.begin (source, null, (obj, result) => {
            bool refused = false;
            try {
                session.open_async.end (result);
            } catch (Error error) {
                refused = true;
            }
            assert (refused);
            assert (session.state == MediaKit.PlaybackState.ERROR);
            assert (session.last_error != null);
            session.close ();
            assert (session.state == MediaKit.PlaybackState.EMPTY);
            assert (session.source == null);
            loop.quit ();
        });
        loop.run ();
    } catch (Error error) {
        assert_not_reached ();
    }
}

/** Ensures cancellation does not leave a half-open playback session. */
private void test_canceled_open () {
    var loop = new MainLoop ();
    var session = new MediaKit.MediaSession ();
    var cancellation = new Cancellable ();
    cancellation.cancel ();
    try {
        var source = new MediaKit.MediaSource.for_path ("/tmp/sample.mp4");
        Idle.add (() => {
            session.open_async.begin (source, cancellation, (obj, result) => {
                bool rejected = false;
                try {
                    session.open_async.end (result);
                } catch (Error error) {
                    rejected = true;
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

/** Registers focused public-API behavior tests without any media fixtures. */
int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/media/core/source", test_source_contract);
    Test.add_func ("/media/core/source-rejection", test_source_rejection);
    Test.add_func ("/media/core/unavailable", test_unavailable_contract);
    Test.add_func ("/media/core/open-failure", test_open_failure);
    Test.add_func ("/media/core/canceled-open", test_canceled_open);
    return Test.run ();
}
