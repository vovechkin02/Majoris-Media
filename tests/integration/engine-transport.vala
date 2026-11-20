/** Command-line value supplied by Meson for this test process. */
private static string filename;

/** Opens a standalone 192-byte-packet M2TS fixture as a regular media source. */
private void test_transport_stream (string filename) {
    var loop = new MainLoop ();
    var session = new MediaKit.MediaSession ();
    bool opened = false;
    uint watchdog_id = 0;
    watchdog_id = Timeout.add_seconds (8, () => {
        watchdog_id = 0;
        loop.quit ();
        return Source.REMOVE;
    });
    try {
        var stream = new MediaKit.MediaSource.for_transport_stream (filename);
        assert (!stream.is_disc);
        session.open_async.begin (stream, null, (object, result) => {
            try {
                session.open_async.end (result);
                opened = true;
                assert (session.state == MediaKit.PlaybackState.READY);
                assert (session.source != null && !session.source.is_disc);
                assert (session.disc_titles.get_n_items () == 0);
                assert (!session.disc_menu_supported);
                session.play ();
                session.pause ();
            } catch (Error error) {
                Test.message ("Transport stream open failed: %s", error.message);
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
    assert (opened);
    assert (session.state == MediaKit.PlaybackState.EMPTY);
}

/** Runs only a bounded real-engine transport-stream integration check. */
int main (string[] args) {
    Test.init (ref args);
    if (args.length < 2) {
        return 2;
    }
    filename = args[1];
    Test.add_func ("/media/integration/stage6-standalone-m2ts", () => {
        test_transport_stream (filename);
    });
    return Test.run ();
}
