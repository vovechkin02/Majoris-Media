[CCode (gir_namespace = "MediaKitGtk", gir_version = "1.0")]
namespace MediaKitGtk {
    /** A neutral, embeddable media surface; Stage 1 intentionally renders no frames. */
    [CCode (cname = "MediaKitView")]
    [GtkTemplate (ui = "/com/majoris/MediaKitGtk/ui/media-view.ui")]
    public sealed class MediaView : Gtk.Box {
        /** Session presented by this control; null is the empty-view state. */
        public MediaKit.MediaSession? session {
            get {
                return current_session;
            }
            set {
                if (current_session == value) {
                    return;
                }

                disconnect_session ();
                current_session = value;
                if (current_session != null) {
                    state_handler_id = current_session.state_changed.connect (on_state_changed);
                }
                update_status ();
            }
        }

        /** Status overlay showing explicit unavailability while rendering is absent. */
        [GtkChild]
        private unowned Gtk.Label status_label;

        /** Presentation area reserved for a real rendering widget in Stage 2. */
        [GtkChild]
        private unowned Gtk.Box render_host;

        /** The retained playback session, disconnected on replacement/disposal. */
        private MediaKit.MediaSession? current_session;

        /** Signal connection token owned by this view. */
        private ulong state_handler_id = 0;

        /** Instantiates the XML template without creating any playback engine. */
        public MediaView () {
            Object ();
        }

        /** Ensures that native template widgets and labels are initialized. */
        construct {
            update_status ();
        }

        /** Reflects session transitions without storing duplicate state. */
        private void on_state_changed (MediaKit.PlaybackState state) {
            update_status ();
        }

        /** Reports actual session state; no misleading video placeholder is displayed. */
        private void update_status () {
            if (current_session == null) {
                status_label.label = "No media loaded";
                return;
            }

            switch (current_session.state) {
            case MediaKit.PlaybackState.OPENING:
                status_label.label = "Opening media...";
                break;
            case MediaKit.PlaybackState.ERROR:
                status_label.label = current_session.last_error ?? "Playback failed";
                break;
            case MediaKit.PlaybackState.EMPTY:
                status_label.label = "No media loaded";
                break;
            default:
                status_label.label = "Playback renderer unavailable (Stage 1)";
                break;
            }
        }

        /** Disconnects an owned signal to prevent cycles or late callbacks. */
        private void disconnect_session () {
            if (current_session != null && state_handler_id != 0) {
                SignalHandler.disconnect (current_session, state_handler_id);
                state_handler_id = 0;
            }
            current_session = null;
        }

        /** Releases the signal subscription when GTK disposes of the widget. */
        protected override void dispose () {
            disconnect_session ();
            base.dispose ();
        }
    }
}
