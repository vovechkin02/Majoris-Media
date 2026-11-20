/** Command-line value supplied by Meson for this test process. */
private static string filename;

/** Qualifies the new engine options without claiming HDR output on headless audio. */
private void test_video_policy_engine (string filename) {
    var options = new MediaKit.PlaybackOptions ();
    options.tone_mapping = MediaKit.ToneMappingAlgorithm.BT2390;
    options.video_quality = MediaKit.VideoQualityPolicy.HIGH_QUALITY;
    var session = new MediaKit.MediaSession (options);
    var loop = new MainLoop ();
    bool loaded = false;
    uint watchdog_id = 0;
    watchdog_id = Timeout.add_seconds (10, () => {
        Test.message ("Timed out waiting for video policy engine load");
        loop.quit ();
        return Source.REMOVE;
    });
    try {
        var source = new MediaKit.MediaSource.for_path (filename);
        session.open_async.begin (source, null, (object, result) => {
            try {
                session.open_async.end (result);
                loaded = session.state == MediaKit.PlaybackState.READY;
            } catch (Error error) {
                Test.message ("Video policy initialization failed: %s", error.message);
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
    assert (loaded);
}

/** Executes the representative policy combination with a deterministic audio fixture. */
int main (string[] args) {
    Test.init (ref args);
    assert (args.length == 2);
    filename = args[1];
    Test.add_func ("/media/integration/engine-video-policy", () => {
        test_video_policy_engine (filename);
    });
    return Test.run ();
}
