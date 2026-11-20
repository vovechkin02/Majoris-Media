/** Minimal consumer proving that the media API can be hosted in a GTK window. */
private class DemoApplication : Gtk.Application {
    /** Creates the example without changing system theme or application settings. */
    public DemoApplication () {
        Object (application_id: "com.majoris.MediaKitDemo");
    }

    /** Creates an embeddable view and controls bound to one session. */
    protected override void activate () {
        var window = new Gtk.ApplicationWindow (this);
        window.title = "Majoris Media — Stage 1";
        window.set_default_size (800, 480);

        var layout = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        var session = new MediaKit.MediaSession ();
        var view = new MediaKitGtk.MediaView ();
        var controls = new MediaKitGtk.MediaControls ();
        view.session = session;
        controls.session = session;
        layout.append (view);
        layout.append (controls);
        window.set_child (layout);
        window.present ();
    }
}

/** Delegates the application's lifecycle to GTK. */
int main (string[] args) {
    return new DemoApplication ().run (args);
}
