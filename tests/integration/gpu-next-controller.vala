/** Command-line value supplied by Meson for this test process. */
private static string support_path;

/** Exercises the independently windowed player against a controlled local IPC double. */
private void test_gpu_next_controller (string support_path) {
    var path = Environment.get_variable ("PATH") ?? "";
    Environment.set_variable ("PATH", support_path + ":" + path, true);
    Environment.set_variable ("WAYLAND_DISPLAY", "majoris-test-wayland", true);
    var loop = new MainLoop ();
    var player = new MediaKit.GpuNextWindow ();
    bool finished = false;
    uint timeout_id = 0;
    timeout_id = Timeout.add_seconds (15, () => {
        timeout_id = 0;
        player.close ();
        loop.quit ();
        return Source.REMOVE;
    });
    try {
        var source = new MediaKit.MediaSource.for_path ("/tmp/test-video.mkv");
        player.open_async.begin (source, null, null, (obj, result) => {
            try {
                player.open_async.end (result);
                assert (player.running && player.ready);
                player.set_paused_async.begin (true, null, (sender, pause_result) => {
                    try {
                        player.set_paused_async.end (pause_result);
                        player.seek_async.begin (2500000, null, (seek_sender, seek_result) => {
                            try {
                                player.seek_async.end (seek_result);
                                player.query_status_async.begin (null,
                                    (query_sender, query_result) => {
                                    try {
                                        var snapshot = player.query_status_async.end (query_result);
                                        assert (snapshot.paused);
                                        assert (snapshot.position_us == 2500000);
                                        assert (snapshot.video_output == "gpu-next");
                                        assert (snapshot.source_primaries == "bt.2020");
                                        assert (snapshot.source_transfer == "pq");
                                        assert (snapshot.output_primaries == "bt.709");
                                        assert (snapshot.output_transfer == "bt.1886");
                                        assert (snapshot.native_hdr !=
                                            MediaKit.CapabilityStatus.AVAILABLE);
                                        finished = true;
                                    } catch (Error error) {
                                        warning ("Status IPC test failed: %s", error.message);
                                    }
                                    player.close ();
                                    loop.quit ();
                                });
                            } catch (Error error) {
                                warning ("Seek IPC test failed: %s", error.message);
                                player.close ();
                                loop.quit ();
                            }
                        });
                    } catch (Error error) {
                        warning ("Pause IPC test failed: %s", error.message);
                        player.close ();
                        loop.quit ();
                    }
                });
            } catch (Error error) {
                warning ("Opening IPC test failed: %s", error.message);
                player.close ();
                loop.quit ();
            }
        });
    } catch (Error error) {
        assert_not_reached ();
    }
    loop.run ();
    if (timeout_id != 0) {
        Source.remove (timeout_id);
    }
    assert (finished);
    assert (!player.running && !player.ready);
}

/** Registers only one process-boundary test; no GPU device is needed. */
int main (string[] args) {
    Test.init (ref args);
    assert (args.length == 2);
    support_path = args[1];
    Test.add_func ("/media/integration/gpu-next-controller", () => {
        test_gpu_next_controller (support_path);
    });
    return Test.run ();
}
