[CCode (gir_namespace = "MediaKitGtk", gir_version = "1.0")]
namespace MediaKitGtk {
    /** Optional neutral transport control; stays disabled until playback works. */
    [CCode (cname = "MediaKitControls")]
    [GtkTemplate (ui = "/com/majoris/MediaKitGtk/ui/media-controls.ui")]
    public sealed class MediaControls : Gtk.Box {
        /** Transport session; can be replaced without retaining stale listeners. */
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
                update_controls ();
            }
        }

        /** Play control remains disabled until operational playback exists. */
        [GtkChild]
        private unowned Gtk.Button play_button;

        /** Human-readable status derived from the attached session. */
        [GtkChild]
        private unowned Gtk.Label status_label;

        /** Current session owned by this controls instance. */
        private MediaKit.MediaSession? current_session;

        /** GTK signal handler ID for safe replacement and disposal. */
        private ulong state_handler_id = 0;

        /** Creates a standalone controls widget, without an application toolbar. */
        public MediaControls () {
            Object ();
        }

        /** Populates the initial control state after template construction. */
        construct {
            update_controls ();
        }

        /** Responds to state changes using the current session as source of truth. */
        private void on_state_changed (MediaKit.PlaybackState state) {
            update_controls ();
        }

        /** Keeps action disabled rather than making a button that silently does nothing. */
        private void update_controls () {
            play_button.sensitive = false;
            status_label.label = current_session == null
                ? "No playback session"
                : "Playback unavailable (Stage 1)";
        }

        /** Breaks the session/widget reference cycle introduced by subscriptions. */
        private void disconnect_session () {
            if (current_session != null && state_handler_id != 0) {
                SignalHandler.disconnect (current_session, state_handler_id);
                state_handler_id = 0;
            }
            current_session = null;
        }

        /** Removes signal subscriptions during widget destruction. */
        protected override void dispose () {
            disconnect_session ();
            base.dispose ();
        }
    }
}
