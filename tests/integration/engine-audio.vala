/** Validates an actual decoded multichannel source without demanding an HDMI receiver. */
private void test_surround_metadata (string filename, string expected_codec) {
    var session = new MediaKit.MediaSession ();
    var loop = new MainLoop ();
    bool loaded = false;
    bool matching_track = false;
    uint watchdog_id = Timeout.add_seconds (12, () => {
        watchdog_id = 0;
        loop.quit ();
        return Source.REMOVE;
    });
    try {
        var source = new MediaKit.MediaSource.for_path (filename);
        session.open_async.begin (source, null, (object, result) => {
            try {
                session.open_async.end (result);
                loaded = true;
                for (uint index = 0; index < session.tracks.get_n_items (); index++) {
                    var track = (MediaKit.MediaTrack) session.tracks.get_item (index);
                    if (track.kind == MediaKit.TrackKind.AUDIO &&
                        track.codec == expected_codec) {
                        matching_track = true;
                    }
                }
                assert (session.source_audio.spatial_format ==
                    MediaKit.SpatialAudioFormat.UNKNOWN);
                assert (session.capabilities.encoded_audio ==
                    MediaKit.CapabilityStatus.UNVERIFIED);
                loop.quit ();
            } catch (Error error) {
                Test.message ("Surround source load failed: %s", error.message);
                loop.quit ();
            }
        });
        loop.run ();
    } catch (Error error) {
        assert_not_reached ();
    }
    if (watchdog_id != 0) {
        Source.remove (watchdog_id);
    }
    assert (loaded);
    assert (matching_track);
    session.close ();
    assert (session.source_audio.codec == "");
    assert (session.audio_devices.get_n_items () == 0);
    assert (session.audio_output.transport == MediaKit.AudioTransportState.UNKNOWN);
}

/** Registers one focused runtime source-format check for each included test file. */
int main (string[] args) {
    Test.init (ref args);
    assert (args.length == 3);
    string filename = args[1];
    string codec = args[2];
    Test.add_func ("/media/audio/source-metadata", () => {
        test_surround_metadata (filename, codec);
    });
    return Test.run ();
}
