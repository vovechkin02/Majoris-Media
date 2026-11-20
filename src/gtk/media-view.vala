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
                    state_handler_id = current_session.state_changed.connect (on_state_changed);
                    output_handler_id = current_session.output_changed.connect (on_output_changed);
                }
                setup_renderer ();
                update_status ();
            }
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

        /** Native frame-update signal subscription. */
        private ulong frame_handler_id = 0;

        /** Creates a template-backed widget without starting playback. */
        public MediaView () {
            Object ();
        }

        /** Subscribes to GL context lifecycle and registers the frame draw callback. */
        construct {
            render_area.set_auto_render (false);
            render_area.realize.connect (on_realize);
            render_area.unrealize.connect (on_unrealize);
            render_area.render.connect ((context) => {
                return render_frame ();
            });
            update_status ();
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
                render_failure = null;
                frame_handler_id = output.update_requested.connect (() => {
                    render_area.queue_render ();
                });
                render_area.queue_render ();
            } catch (Error error) {
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
