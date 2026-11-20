[CCode (gir_namespace = "MediaKitGtk", gir_version = "1.0")]
namespace MediaKitGtk {
    /** Optional GTK4 transport controls connected to an independent MediaSession. */
    [CCode (cname = "MediaKitControls")]
    [GtkTemplate (ui = "/com/majoris/MediaKitGtk/ui/media-controls.ui")]
    public sealed class MediaControls : Gtk.Box {
        /** Playback session that receives transport and seek requests. */
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
                    position_handler_id = current_session.position_changed.connect ((value) => {
                        update_position ();
                    });
                    duration_handler_id = current_session.duration_changed.connect ((value) => {
                        update_position ();
                    });
                }
                update_controls ();
            }
        }

        /** Toggles play/pause, using the session as the only source of truth. */
        [GtkChild]
        private unowned Gtk.Button play_button;

        /** Explicit stop control for the active source. */
        [GtkChild]
        private unowned Gtk.Button stop_button;

        /** Seek position in seconds, converted to microseconds at the core boundary. */
        [GtkChild]
        private unowned Gtk.Scale seek_scale;

        /** Human-readable playback position and duration. */
        [GtkChild]
        private unowned Gtk.Label status_label;

        /** Owned session whose observers are disconnected upon replacement. */
        private MediaKit.MediaSession? current_session;

        /** State-change subscription identifier. */
        private ulong state_handler_id = 0;

        /** Position-change subscription identifier. */
        private ulong position_handler_id = 0;

        /** Duration-change subscription identifier. */
        private ulong duration_handler_id = 0;

        /** Prevents a programmatic slider update from scheduling an unnecessary seek. */
        private bool updating_position = false;

        /** One short debounce timer for mouse/keyboard seek requests. */
        private uint seek_timeout_id = 0;

        /** Creates a neutral XML template-backed transport bar. */
        public MediaControls () {
            Object ();
        }

        /** Wires GTK controls without introducing application-specific styling. */
        construct {
            play_button.clicked.connect (on_play_clicked);
            stop_button.clicked.connect (on_stop_clicked);
            seek_scale.value_changed.connect (on_seek_value_changed);
            update_controls ();
        }

        /** Reflects a new playback state without duplicating backend state. */
        private void on_state_changed (MediaKit.PlaybackState state) {
            update_controls ();
        }

        /** Submits the appropriate play or pause operation and displays real errors. */
        private void on_play_clicked () {
            if (current_session == null) {
                return;
            }
            try {
                if (current_session.state == MediaKit.PlaybackState.PLAYING) {
                    current_session.pause ();
                } else {
                    current_session.play ();
                }
            } catch (Error error) {
                status_label.label = error.message;
            }
        }

        /** Stops the stream when the session has an active source. */
        private void on_stop_clicked () {
            if (current_session == null) {
                return;
            }
            try {
                current_session.stop ();
            } catch (Error error) {
                status_label.label = error.message;
            }
        }

        /** Debounces user slider requests rather than seeking every intermediate pixel. */
        private void on_seek_value_changed () {
            if (updating_position || current_session == null) {
                return;
            }
            if (seek_timeout_id != 0) {
                Source.remove (seek_timeout_id);
            }
            seek_timeout_id = Timeout.add (150, () => {
                seek_timeout_id = 0;
                if (current_session == null) {
                    return Source.REMOVE;
                }
                try {
                    int64 target_us = (int64) (seek_scale.get_value () * 1000000.0);
                    current_session.seek (target_us);
                } catch (Error error) {
                    status_label.label = error.message;
                }
                return Source.REMOVE;
            });
        }

        /** Applies control state and descriptive button accessibility text. */
        private void update_controls () {
            var state = current_session == null
                ? MediaKit.PlaybackState.EMPTY : current_session.state;
            bool playable = state == MediaKit.PlaybackState.READY ||
                state == MediaKit.PlaybackState.PLAYING ||
                state == MediaKit.PlaybackState.PAUSED ||
                state == MediaKit.PlaybackState.STOPPED ||
                state == MediaKit.PlaybackState.ENDED;
            play_button.sensitive = playable;
            stop_button.sensitive = state == MediaKit.PlaybackState.PLAYING ||
                state == MediaKit.PlaybackState.PAUSED ||
                state == MediaKit.PlaybackState.READY;
            play_button.icon_name = state == MediaKit.PlaybackState.PLAYING
                ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            play_button.tooltip_text = state == MediaKit.PlaybackState.PLAYING
                ? "Pause" : "Play";
            update_position ();
        }

        /** Synchronizes slider and time display without causing a seek feedback loop. */
        private void update_position () {
            int64 duration_us = current_session == null ? 0 : current_session.duration_us;
            int64 position_us = current_session == null ? 0 : current_session.position_us;
            updating_position = true;
            seek_scale.sensitive = duration_us > 0 && current_session != null &&
                current_session.state != MediaKit.PlaybackState.OPENING &&
                current_session.state != MediaKit.PlaybackState.ERROR;
            seek_scale.set_range (0.0, duration_us > 0 ? duration_us / 1000000.0 : 1.0);
            seek_scale.set_value (position_us / 1000000.0);
            updating_position = false;
            status_label.label = "%s / %s".printf (
                format_time (position_us), format_time (duration_us)
            );
        }

        /** Converts a microsecond timestamp into readable hours and minutes. */
        private static string format_time (int64 time_us) {
            int64 seconds = time_us > 0 ? time_us / 1000000 : 0;
            int64 minutes = seconds / 60;
            if (minutes >= 60) {
                return "%02d:%02d:%02d".printf (
                    (int) (minutes / 60), (int) (minutes % 60), (int) (seconds % 60)
                );
            }
            return "%02d:%02d".printf ((int) minutes, (int) (seconds % 60));
        }

        /** Disconnects old subscriptions and cancels pending debounce on replacement. */
        private void disconnect_session () {
            if (seek_timeout_id != 0) {
                Source.remove (seek_timeout_id);
                seek_timeout_id = 0;
            }
            if (current_session != null) {
                if (state_handler_id != 0) {
                    SignalHandler.disconnect (current_session, state_handler_id);
                    state_handler_id = 0;
                }
                if (position_handler_id != 0) {
                    SignalHandler.disconnect (current_session, position_handler_id);
                    position_handler_id = 0;
                }
                if (duration_handler_id != 0) {
                    SignalHandler.disconnect (current_session, duration_handler_id);
                    duration_handler_id = 0;
                }
            }
            current_session = null;
        }

        /** Cleans up delayed actions and subscriptions during GTK disposal. */
        protected override void dispose () {
            disconnect_session ();
            base.dispose ();
        }
    }
}
