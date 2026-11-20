[CCode (gir_namespace = "MediaKitGtk", gir_version = "1.0")]
namespace MediaKitGtk {
    /** Neutral GTK4 media presentation widget backed by libmpv's OpenGL render API. */
    [CCode (cname = "MediaKitView")]
    [GtkTemplate (ui = "/com/majoris/MediaKitGtk/ui/media-view.ui")]
    public sealed class MediaView : Gtk.Box {
        /** Session whose current media engine will supply video frames. */
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
                    weak MediaView weak_owner = this;
                    state_handler_id = current_session.state_changed.connect ((state) => {
                        weak_owner?.on_state_changed (state);
                    });
                    output_handler_id = current_session.output_changed.connect (() => {
                        weak_owner?.on_output_changed ();
                    });
                    tracks_handler_id = current_session.tracks_changed.connect (() => {
                        weak_owner?.update_status ();
                    });
                    buffering_handler_id = current_session.buffering_changed.connect (
                        (active, percent) => {
                            weak_owner?.update_status ();
                        }
                    );
                }
                setup_renderer ();
                update_status ();
            }
        }

        /** Host-provided monitor ICC profile; no automatic display detection is assumed. */
        private Bytes? display_icc_profile;

        /** Validates and applies a monitor profile without touching the media source. */
        public void set_display_icc_profile (Bytes? profile) throws Error {
            if (profile != null) {
                var size = profile.get_size ();
                if (size < 128 || size > 4 * 1024 * 1024) {
                    throw new MediaKit.MediaError.INVALID_ARGUMENT (
                        "Display ICC profile must be between 128 bytes and 4 MiB"
                    );
                }
            }
            if (output != null) {
                render_area.make_current ();
                if (render_area.get_error () != null) {
                    throw new MediaKit.MediaError.PLAYBACK_FAILED (
                        "OpenGL context is unavailable for display ICC update"
                    );
                }
                output.set_display_icc_profile (profile);
                render_area.queue_render ();
            }
            display_icc_profile = profile;
        }

        /** Overlay status message shown only for empty, loading or failed streams. */
        [GtkChild]
        private unowned Gtk.Label status_label;

        /** Owns the GL framebuffer and GTK OpenGL context. */
        [GtkChild]
        private unowned Gtk.GLArea render_area;

        /** Strongly referenced session, which may be reassigned by the host. */
        private MediaKit.MediaSession? current_session;

        /** One renderer per session, created only while GtkGLArea has a current context. */
        private MediaKit.OpenGlOutput? output;

        /** Keeps GL setup failures visible until successful renderer creation. */
        private string? render_failure;

        /** Session state signal subscription to remove on replacement. */
        private ulong state_handler_id = 0;

        /** Session render-target invalidation signal subscription. */
        private ulong output_handler_id = 0;

        /** Tracks changes that distinguish video and audio-only streams. */
        private ulong tracks_handler_id = 0;

        /** Buffering-state subscription for an accurate in-widget overlay. */
        private ulong buffering_handler_id = 0;

        /** Native frame-update signal subscription. */
        private ulong frame_handler_id = 0;

        /** Creates a template-backed widget without starting playback. */
        public MediaView () {
            Object ();
        }

        /** Subscribes to GL context lifecycle and registers the frame draw callback. */
        construct {
            render_area.set_auto_render (false);
            render_area.set_focusable (true);
            weak MediaView weak_owner = this;
            var key_controller = new Gtk.EventControllerKey ();
            key_controller.key_pressed.connect ((keyval, keycode, state) => {
                return weak_owner != null && weak_owner.handle_disc_key (keyval);
            });
            render_area.add_controller (key_controller);
            render_area.realize.connect (() => {
                weak_owner?.on_realize ();
            });
            render_area.unrealize.connect (() => {
                weak_owner?.on_unrealize ();
            });
            render_area.render.connect ((context) => {
                return weak_owner == null || weak_owner.render_frame ();
            });
            update_status ();
        }

        /** Routes directional keys only while an interactive disc menu is active. */
        private bool handle_disc_key (uint keyval) {
            if (current_session == null || !current_session.disc_menu_supported) {
                return false;
            }
            MediaKit.DiscMenuAction action;
            if (keyval == Gdk.Key.F10) {
                action = MediaKit.DiscMenuAction.MENU;
            } else {
                if (!current_session.disc_menu_active) {
                    return false;
                }
                switch (keyval) {
                case Gdk.Key.Up:
                    action = MediaKit.DiscMenuAction.UP;
                    break;
                case Gdk.Key.Down:
                    action = MediaKit.DiscMenuAction.DOWN;
                    break;
                case Gdk.Key.Left:
                    action = MediaKit.DiscMenuAction.LEFT;
                    break;
                case Gdk.Key.Right:
                    action = MediaKit.DiscMenuAction.RIGHT;
                    break;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    action = MediaKit.DiscMenuAction.SELECT;
                    break;
                case Gdk.Key.Escape:
                    action = MediaKit.DiscMenuAction.BACK;
                    break;
                default:
                    return false;
                }
            }
            try {
                current_session.navigate_disc_menu (action);
            } catch (Error error) {
                warning ("Disc navigation rejected: %s", error.message);
            }
            return true;
        }

        /** Creates a renderer after GTK has established a valid OpenGL context. */
        private void on_realize () {
            setup_renderer ();
        }

        /** Releases the GPU renderer before its GTK context is destroyed. */
        private void on_unrealize () {
            release_renderer ();
        }

        /** Recreates GPU presentation after a session replaces the native engine. */
        private void on_output_changed () {
            release_renderer ();
            setup_renderer ();
        }

        /** Updates the readable overlay when a session changes lifecycle state. */
        private void on_state_changed (MediaKit.PlaybackState state) {
            update_status ();
            if (state == MediaKit.PlaybackState.READY) {
                render_area.queue_render ();
            }
        }

        /** Attaches one libmpv renderer without inventing a second GL context. */
        private void setup_renderer () {
            if (output != null || current_session == null || current_session.source == null ||
                !render_area.get_realized ()) {
                return;
            }
            render_area.make_current ();
            if (render_area.get_error () != null) {
                render_failure = "OpenGL context is unavailable";
                status_label.label = render_failure;
                status_label.visible = true;
                return;
            }
            try {
                output = current_session.create_opengl_output ();
                if (display_icc_profile != null) {
                    output.set_display_icc_profile (display_icc_profile);
                }
                render_failure = null;
                weak MediaView weak_owner = this;
                frame_handler_id = output.update_requested.connect (() => {
                    if (weak_owner != null) {
                        weak_owner.render_area.queue_render ();
                    }
                });
                render_area.queue_render ();
            } catch (Error error) {
                release_renderer ();
                warning ("Unable to attach media video output: %s", error.message);
                render_failure = error.message;
                status_label.label = render_failure;
                status_label.visible = true;
            }
        }

        /** Draws into the GLArea framebuffer at the physical pixel dimensions. */
        private bool render_frame () {
            if (output == null) {
                return true;
            }
            render_area.attach_buffers ();
            int width_px = render_area.get_width () * render_area.get_scale_factor ();
            int height_px = render_area.get_height () * render_area.get_scale_factor ();
            if (width_px <= 0 || height_px <= 0) {
                return true;
            }
            try {
                output.render_current_frame (width_px, height_px);
            } catch (Error error) {
                warning ("Media frame presentation failed: %s", error.message);
                render_failure = error.message;
                status_label.label = render_failure;
                status_label.visible = true;
            }
            return true;
        }

        /** Destroys native GL objects while the GTK GL context is current. */
        private void release_renderer () {
            if (output == null) {
                return;
            }
            if (frame_handler_id != 0) {
                SignalHandler.disconnect (output, frame_handler_id);
                frame_handler_id = 0;
            }
            if (render_area.get_realized ()) {
                render_area.make_current ();
            }
            output.detach ();
            output = null;
        }

        /** Shows only actual loading, empty and error states over the playback surface. */
        private void update_status () {
            if (current_session == null) {
                status_label.label = "No media loaded";
                status_label.visible = true;
                return;
            }
            if (current_session.state == MediaKit.PlaybackState.ERROR) {
                status_label.label = current_session.last_error ?? "Media playback failed";
                status_label.visible = true;
                return;
            }
            if (current_session.is_buffering) {
                int percent = current_session.buffering_percent;
                status_label.label = percent < 0 ? "Buffering…"
                    : "Buffering… %d%%".printf (percent);
                status_label.visible = true;
                return;
            }
            bool has_video = false;
            for (uint index = 0; index < current_session.tracks.get_n_items (); index++) {
                var track = (MediaKit.MediaTrack) current_session.tracks.get_item (index);
                if (track.kind == MediaKit.TrackKind.VIDEO && track.selected) {
                    has_video = true;
                    break;
                }
            }
            if (!has_video && current_session.state != MediaKit.PlaybackState.OPENING &&
                current_session.state != MediaKit.PlaybackState.EMPTY &&
                current_session.state != MediaKit.PlaybackState.ERROR) {
                switch (current_session.state) {
                case MediaKit.PlaybackState.PAUSED:
                    status_label.label = "Audio paused";
                    break;
                case MediaKit.PlaybackState.ENDED:
                    status_label.label = "Audio playback ended";
                    break;
                case MediaKit.PlaybackState.STOPPED:
                    status_label.label = "Audio stopped";
                    break;
                default:
                    status_label.label = "Audio playback";
                    break;
                }
                status_label.visible = true;
                return;
            }
            if (render_failure != null) {
                status_label.label = render_failure;
                status_label.visible = true;
                return;
            }
            switch (current_session.state) {
            case MediaKit.PlaybackState.OPENING:
                status_label.label = "Opening media...";
                status_label.visible = true;
                break;
            case MediaKit.PlaybackState.ERROR:
                status_label.label = current_session.last_error ?? "Media playback failed";
                status_label.visible = true;
                break;
            case MediaKit.PlaybackState.EMPTY:
                status_label.label = "No media loaded";
                status_label.visible = true;
                break;
            default:
                status_label.visible = false;
                break;
            }
        }

        /** Disconnects the old session without stopping playback in other consumers. */
        private void disconnect_session () {
            release_renderer ();
            if (current_session != null) {
                if (state_handler_id != 0) {
                    SignalHandler.disconnect (current_session, state_handler_id);
                    state_handler_id = 0;
                }
                if (output_handler_id != 0) {
                    SignalHandler.disconnect (current_session, output_handler_id);
                    output_handler_id = 0;
                }
                if (tracks_handler_id != 0) {
                    SignalHandler.disconnect (current_session, tracks_handler_id);
                    tracks_handler_id = 0;
                }
                if (buffering_handler_id != 0) {
                    SignalHandler.disconnect (current_session, buffering_handler_id);
                    buffering_handler_id = 0;
                }
            }
            current_session = null;
            render_failure = null;
        }

        /** Tears down session listeners and the embedded GL renderer on GTK disposal. */
        protected override void dispose () {
            disconnect_session ();
            base.dispose ();
        }
    }
}
