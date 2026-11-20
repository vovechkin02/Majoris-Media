/** Command-line value supplied by Meson for this test process. */
private static string filename;

/** Validates actual WAV loading and playback-control entry points through libmpv. */
private void test_playback_roundtrip (string filename) {
    var loop = new MainLoop ();
    var session = new MediaKit.MediaSession ();
    uint watchdog_id = 0;
    watchdog_id = Timeout.add_seconds (10, () => {
        watchdog_id = 0;
        Test.message ("Timed out waiting for libmpv file-loaded event");
        loop.quit ();
        return Source.REMOVE;
    });
    bool completed = false;
    try {
        var source = new MediaKit.MediaSource.for_path (filename);
        session.open_async.begin (source, null, (object, result) => {
            try {
                session.open_async.end (result);
                assert (session.state == MediaKit.PlaybackState.READY);
                session.play ();
                assert (session.state == MediaKit.PlaybackState.PLAYING);
                session.pause ();
                assert (session.state == MediaKit.PlaybackState.PAUSED);
                session.seek (100000);
                session.stop ();
                assert (session.state == MediaKit.PlaybackState.STOPPED);
                session.play ();
                assert (session.state == MediaKit.PlaybackState.PLAYING);
                completed = true;
            } catch (Error error) {
                Test.message ("libmpv roundtrip failed: %s", error.message);
            }
            session.close ();
            loop.quit ();
        });
        loop.run ();
    } catch (Error error) {
        assert_not_reached ();
    }
    if (watchdog_id != 0) {
        Source.remove (watchdog_id);
    }
    assert (completed);
    assert (session.state == MediaKit.PlaybackState.EMPTY);
}

/** Runs the opt-in native playback smoke test with an actual short audio fixture. */
int main (string[] args) {
    Test.init (ref args);
    assert (args.length == 2);
    filename = args[1];
    Test.add_func ("/media/integration/engine-playback", () => {
        test_playback_roundtrip (filename);
    });
    return Test.run ();
}
