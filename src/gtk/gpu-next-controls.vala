[CCode (gir_namespace = "MediaKitGtk", gir_version = "1.0")]
namespace MediaKitGtk {
    /** Optional GTK transport controls for a separately windowed gpu-next process. */
    [CCode (cname = "MediaKitGpuNextControls")]
    [GtkTemplate (ui = "/com/majoris/MediaKitGtk/ui/gpu-next-controls.ui")]
    public sealed class GpuNextControls : Gtk.Box {
        /** External playback owner; never substitutes for the embedded MediaSession. */
        public MediaKit.GpuNextWindow? player {
            get {
                return current_player;
            }
            set {
                if (current_player == value) {
                    return;
                }
                disconnect_player ();
                current_player = value;
                if (current_player != null) {
                    weak GpuNextControls weak_self = this;
                    ready_handler_id = current_player.notify["ready"].connect (() => {
                        weak_self?.refresh_buttons ();
                    });
                    exit_handler_id = current_player.finished.connect ((successful, status) => {
                        if (weak_self != null) {
                            weak_self.refresh_buttons ();
                            weak_self.status_label.label = successful
                                ? "Advanced playback ended" : "Advanced playback exited";
                        }
                    });
                }
                refresh_buttons ();
            }
        }

        /** Resume playback in the external renderer. */
        [GtkChild]
        private unowned Gtk.Button play_button;

        /** Pause playback in the external renderer. */
        [GtkChild]
        private unowned Gtk.Button pause_button;

        /** Seek backward relative to the observed engine position. */
        [GtkChild]
        private unowned Gtk.Button back_button;

        /** Seek forward relative to the observed engine position. */
        [GtkChild]
        private unowned Gtk.Button forward_button;

        /** Refresh read-only state without background polling. */
        [GtkChild]
        private unowned Gtk.Button refresh_button;

        /** Status of the separate renderer, with no implied HDR verification. */
        [GtkChild]
        private unowned Gtk.Label status_label;

        /** Current external owner, if one was assigned. */
        private MediaKit.GpuNextWindow? current_player;

        /** Signal subscription for readiness changes. */
        private ulong ready_handler_id = 0;

        /** Signal subscription for external child termination. */
        private ulong exit_handler_id = 0;

        /** Connects the neutral XML controls to asynchronous Core operations. */
        public GpuNextControls () {
            Object ();
            play_button.clicked.connect (() => {
                set_paused (false);
            });
            pause_button.clicked.connect (() => {
                set_paused (true);
            });
            back_button.clicked.connect (() => {
                seek_relative (-10000000);
            });
            forward_button.clicked.connect (() => {
                seek_relative (10000000);
            });
            refresh_button.clicked.connect (() => {
                refresh_status ();
            });
            refresh_buttons ();
        }

        /** Requests an explicit pause value without relying on a blind toggle. */
        private void set_paused (bool paused) {
            var current = current_player;
            if (current == null || !current.ready) {
                return;
            }
            weak GpuNextControls weak_self = this;
            current.set_paused_async.begin (paused, null, (object, result) => {
                try {
                    current.set_paused_async.end (result);
                    weak_self?.refresh_status ();
                } catch (Error error) {
                    weak_self?.show_error (error.message);
                }
            });
        }

        /** Applies a ten-second relative seek using the engine's observed position. */
        private void seek_relative (int64 offset_us) {
            var current = current_player;
            if (current == null || !current.ready) {
                return;
            }
            weak GpuNextControls weak_self = this;
            current.query_status_async.begin (null, (object, result) => {
                try {
                    var snapshot = current.query_status_async.end (result);
                    if (snapshot.position_us < 0) {
                        return;
                    }
                    int64 position = snapshot.position_us + offset_us;
                    if (position < 0) {
                        position = 0;
                    }
                    current.seek_async.begin (position, null, (sender, seek_result) => {
                        try {
                            current.seek_async.end (seek_result);
                            weak_self?.refresh_status ();
                        } catch (Error error) {
                            weak_self?.show_error (error.message);
                        }
                    });
                } catch (Error error) {
                    weak_self?.show_error (error.message);
                }
            });
        }

        /** Refreshes the separately windowed engine's read-only playback state. */
        private void refresh_status () {
            var current = current_player;
            if (current == null || !current.ready) {
                refresh_buttons ();
                return;
            }
            weak GpuNextControls weak_self = this;
            current.query_status_async.begin (null, (object, result) => {
                try {
                    var snapshot = current.query_status_async.end (result);
                    if (weak_self != null && weak_self.current_player == current) {
                        int64 seconds = snapshot.position_us >= 0
                            ? snapshot.position_us / 1000000 : 0;
                        int minutes = (int) (seconds / 60);
                        int remainder = (int) (seconds % 60);
                        weak_self.status_label.label = "%02d:%02d · %s".printf (
                            minutes, remainder,
                            snapshot.paused ? "Paused" : "Playing"
                        );
                    }
                } catch (Error error) {
                    weak_self?.show_error (error.message);
                }
            });
        }

        /** Shows one actionable IPC error in the current transport controls. */
        private void show_error (string reason) {
            status_label.label = "Advanced playback unavailable";
            status_label.tooltip_text = reason;
            refresh_buttons ();
        }

        /** Enables controls only while the external process can receive IPC. */
        private void refresh_buttons () {
            bool available = current_player != null && current_player.ready;
            play_button.sensitive = available;
            pause_button.sensitive = available;
            back_button.sensitive = available;
            forward_button.sensitive = available;
            refresh_button.sensitive = available;
            if (!available) {
                status_label.label = "Advanced renderer inactive";
            }
        }

        /** Disconnects callbacks when another process owner is selected. */
        private void disconnect_player () {
            if (current_player != null) {
                if (ready_handler_id != 0) {
                    SignalHandler.disconnect (current_player, ready_handler_id);
                    ready_handler_id = 0;
                }
                if (exit_handler_id != 0) {
                    SignalHandler.disconnect (current_player, exit_handler_id);
                    exit_handler_id = 0;
                }
            }
            current_player = null;
        }

        /** Releases observer subscriptions before the GTK widget is destroyed. */
        ~GpuNextControls () {
            disconnect_player ();
        }
    }
}
