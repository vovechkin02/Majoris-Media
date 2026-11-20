/** Verifies the experimental HDR view remains unverified before any GPU output. */
private void test_initial_hdr_view () {
    var view = new MediaKitGtk.HdrMediaView ();
    assert (!view.pq_texture_submitted);
    assert (view.presentation == MediaKit.HdrPresentation.UNVERIFIED);
    var options = new MediaKit.PlaybackOptions ();
    options.hdr_policy = MediaKit.HdrOutputPolicy.EXPERIMENTAL_PQ_TEXTURE;
    var session = new MediaKit.MediaSession (options);
    view.session = session;
    assert (view.session == session);
    assert (!view.pq_texture_submitted);
    view.session = null;
    assert (view.session == null);
}

/** Registers only the opt-in HDR widget contract, without claiming GPU validation. */
int main (string[] args) {
    Test.init (ref args);
    Gtk.init ();
    Test.add_func ("/media/gtk/experimental-hdr-view", test_initial_hdr_view);
    return Test.run ();
}
