/** Tests that two GTK consumer widgets can share a session and release it safely. */
private void test_widget_binding () {
    var session = new MediaKit.MediaSession ();
    var view = new MediaKitGtk.MediaView ();
    var controls = new MediaKitGtk.MediaControls ();
    view.session = session;
    controls.session = session;
    assert (view.session == session);
    assert (controls.session == session);
    view.session = null;
    controls.session = null;
    assert (view.session == null);
    assert (controls.session == null);
}

/** Registers the minimal GTK integration check when a headless GDK backend exists. */
int main (string[] args) {
    Test.init (ref args);
    Gtk.init ();
    Test.add_func ("/media/gtk/widget-binding", test_widget_binding);
    return Test.run ();
}
