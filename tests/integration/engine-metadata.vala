/** Exercises the Stage 3 live metadata and independent playback control contract. */
private void test_multistream_contract (string filename) {
    var session = new MediaKit.MediaSession ();
    var loop = new MainLoop ();
    bool loaded = false;
    bool selected_audio = false;
    bool selected_chapter = false;
    bool subtitles_hidden = false;
    string? other_audio_id = null;
    uint watchdog_id = 0;

    session.tracks_changed.connect (() => {
        if (other_audio_id != null && session.selected_track_id (
            MediaKit.TrackKind.AUDIO) == other_audio_id) {
            selected_audio = true;
        }
    });
    session.chapter_changed.connect ((index) => {
        if (index == 1) {
            selected_chapter = true;
        }
    });
    session.subtitle_visibility_changed.connect ((visible) => {
        if (!visible) {
            subtitles_hidden = true;
        }
    });
    watchdog_id = Timeout.add_seconds (8, () => {
        watchdog_id = 0;
        Test.message ("Stage 3 metadata/control observation timed out");
        loop.quit ();
        return Source.REMOVE;
    });
    try {
        var source = new MediaKit.MediaSource.for_path (filename);
        session.open_async.begin (source, null, (object, result) => {
            try {
                session.open_async.end (result);
                loaded = true;
                assert (session.state == MediaKit.PlaybackState.READY);
                int audio_count = 0;
                int video_count = 0;
                int subtitle_count = 0;
                string? initial_audio = session.selected_track_id (MediaKit.TrackKind.AUDIO);
                for (uint index = 0; index < session.tracks.get_n_items (); index++) {
                    var track = (MediaKit.MediaTrack) session.tracks.get_item (index);
                    switch (track.kind) {
                    case MediaKit.TrackKind.AUDIO:
                        audio_count++;
                        if (track.id != initial_audio) {
                            other_audio_id = track.id;
                        }
                        break;
                    case MediaKit.TrackKind.VIDEO:
                        video_count++;
                        break;
                    case MediaKit.TrackKind.SUBTITLE:
                        subtitle_count++;
                        break;
                    }
                }
                assert (audio_count == 2);
                assert (video_count == 1);
                assert (subtitle_count == 1);
                assert (session.chapters.get_n_items () == 2);
                assert (other_audio_id != null);
                session.select_audio_track (other_audio_id);
                session.set_subtitles_visible (false);
                session.select_chapter (1);
                Timeout.add (1200, () => {
                    loop.quit ();
                    return Source.REMOVE;
                });
            } catch (Error error) {
                Test.message ("Multistream metadata load failed: %s", error.message);
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
    assert (selected_audio);
    assert (selected_chapter);
    assert (subtitles_hidden);
    session.close ();
    assert (session.tracks.get_n_items () == 0);
    assert (session.chapters.get_n_items () == 0);
    assert (session.current_chapter_index == -1);
    assert (!session.is_buffering);
}

/** Registers the representative multistream playback test with a real file. */
int main (string[] args) {
    Test.init (ref args);
    assert (args.length == 2);
    string fixture = args[1];
    Test.add_func ("/media/integration/multistream-metadata", () => {
        test_multistream_contract (fixture);
    });
    return Test.run ();
}
