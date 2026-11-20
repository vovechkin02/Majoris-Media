/** Small interactive host that demonstrates the reusable MediaKit widgets. */
private class DemoApplication : Gtk.Application {
    /** Constructs the demonstration GTK application without extra application state. */
    public DemoApplication () {
        Object (application_id: "com.majoris.MediaKitDemo");
    }

    /** Shows a neutral playback window with a file picker and transport controls. */
    protected override void activate () {
        var window = new Gtk.ApplicationWindow (this);
        window.title = "Majoris Media — Advanced video demo";
        window.set_default_size (960, 600);

        var session = new MediaKit.MediaSession ();
        var view = new MediaKitGtk.MediaView ();
        var controls = new MediaKitGtk.MediaControls ();
        view.session = session;
        controls.session = session;

        var advanced_window = new MediaKit.GpuNextWindow ();
        var advanced_controls = new MediaKitGtk.GpuNextControls ();
        advanced_controls.player = advanced_window;
        var advanced_button = new Gtk.Button.with_label (
            "Advanced video (separate Wayland window)"
        );
        advanced_button.tooltip_text =
            "Requires mpv 0.42+ and Wayland; native HDR must be verified externally";
        advanced_button.clicked.connect (() => {
            var source = session.source;
            if (source == null || advanced_window.running) {
                return;
            }
            advanced_window.open_async.begin (source, null, null, (object, result) => {
                try {
                    advanced_window.open_async.end (result);
                    if (session.state == MediaKit.PlaybackState.PLAYING) {
                        session.pause ();
                    }
                } catch (Error error) {
                    warning ("Advanced video unavailable: %s", error.message);
                }
            });
        });
        window.close_request.connect (() => {
            advanced_window.close ();
            session.close ();
            return false;
        });

        var open_button = new Gtk.Button.with_label ("Open Media");
        open_button.clicked.connect (() => {
            var chooser = new Gtk.FileDialog ();
            chooser.title = "Open media file";
            chooser.open.begin (window, null, (object, result) => {
                try {
                    var selected = chooser.open.end (result);
                    var source = new MediaKit.MediaSource.for_uri (selected.get_uri ());
                    session.open_async.begin (source, null, (sender, load_result) => {
                        try {
                            session.open_async.end (load_result);
                            session.play ();
                        } catch (Error error) {
                            warning ("Media playback failed: %s", error.message);
                        }
                    });
                } catch (IOError.CANCELLED error) {
                    return;
                } catch (Error error) {
                    warning ("Unable to open selected file: %s", error.message);
                }
            });
        });

        var layout = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        layout.append (open_button);
        layout.append (advanced_button);
        layout.append (advanced_controls);
        layout.append (view);
        layout.append (controls);
        window.set_child (layout);
        window.present ();
    }
}

/** Transfers process ownership to the GTK application lifecycle. */
int main (string[] args) {
    return new DemoApplication ().run (args);
}
