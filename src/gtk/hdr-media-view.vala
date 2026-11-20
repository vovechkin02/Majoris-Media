[CCode (gir_namespace = "MediaKitGtk", gir_version = "1.0")]
namespace MediaKitGtk {
    /** Experimental GPU-next GTK video widget presenting BT.2100/PQ GL textures.
     *
     * This class does not claim that a compositor enabled native monitor HDR.
     * A matching patched libmpv and an explicit EXPERIMENTAL_PQ_TEXTURE session
     * policy are required. Frame output remains unverified until tested on a
     * real Wayland compositor and HDR monitor.
     */
    public sealed class HdrMediaView : Gtk.Widget {
        /** Active playback session; replacement safely retires the old GL output. */
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
                    weak HdrMediaView weak_self = this;
                    session_handler = current_session.output_changed.connect (() => {
                        weak_self?.reconnect_renderer ();
                    });
                }
                reconnect_renderer ();
            }
        }

        /** True after an RGBA16F frame was submitted with the BT.2100/PQ tag. */
        public bool pq_texture_submitted { get; private set; default = false; }

        /** A successful PQ submission is not proof of native HDR monitor output. */
        public MediaKit.HdrPresentation presentation {
            get {
                return MediaKit.HdrPresentation.UNVERIFIED;
            }
        }

        /** Reports a GL or renderer error without silently falling back to SDR. */
        public signal void rendering_failed (string message);

        /** Current session, also used by the main-context-only snapshot path. */
        private MediaKit.MediaSession? current_session;

        /** Owning GL context created from the GtkNative's surface at realization. */
        private Gdk.GLContext? gl_context;

        /** Native frame bridge, released before the widget's context disappears. */
        private MediaKitGtkNative.HdrFrame? frame_bridge;

        /** Renderer created inside this widget's current GL context. */
        private MediaKit.OpenGlOutput? output;

        /** Last immutable texture; unchanged snapshots reuse it without rerendering. */
        private Gdk.Texture? last_texture;

        /** True when the source, size, or native video frame changed. */
        private bool needs_frame = true;

        /** Stops retrying on an unsupported GPU until the session is replaced. */
        private bool render_failed = false;

        /** Last submitted physical dimensions used to detect framebuffer resizing. */
        private int last_width_px = 0;

        /** Last submitted physical height, invalidated after context replacement. */
        private int last_height_px = 0;

        /** Live GObject subscriptions disconnected on source replacement or disposal. */
        private ulong session_handler = 0;

        /** Native frame subscription disconnected before output disposal. */
        private ulong frame_handler = 0;

        /** Creates a neutral, non-playing widget without starting libmpv. */
        public HdrMediaView () {
            Object ();
            set_hexpand (true);
            set_vexpand (true);
            set_size_request (320, 180);
        }

        /** Connects a GL context only after the widget becomes realized. */
        protected override void realize () {
            base.realize ();
            try {
                var native = get_native ();
                if (native == null) {
                    throw new MediaKit.MediaError.UNSUPPORTED (
                        "The HDR view requires a realized GTK native surface"
                    );
                }
                var surface = native.get_surface ();
                gl_context = surface.create_gl_context ();
                gl_context.realize ();
                gl_context.make_current ();
                frame_bridge = new MediaKitGtkNative.HdrFrame (gl_context);
                setup_renderer ();
            } catch (Error error) {
                report_failure (error.message);
            }
        }

        /** Releases libmpv rendering before the host destroys the GL context. */
        protected override void unrealize () {
            release_renderer ();
            frame_bridge = null;
            last_texture = null;
            gl_context = null;
            base.unrealize ();
        }

        /** Draws a cached, color-tagged video texture in the GTK snapshot graph. */
        protected override void snapshot (Gtk.Snapshot snapshot) {
            if (!render_failed && output != null && frame_bridge != null &&
                gl_context != null && get_width () > 0 && get_height () > 0) {
                int width_px = get_width () * get_scale_factor ();
                int height_px = get_height () * get_scale_factor ();
                if (width_px != last_width_px || height_px != last_height_px) {
                    output.invalidate_framebuffer ();
                    needs_frame = true;
                    last_width_px = width_px;
                    last_height_px = height_px;
                }
                if (needs_frame) {
                    try {
                        gl_context.make_current ();
                        frame_bridge.begin (width_px, height_px);
                        try {
                            output.render_pq_frame (width_px, height_px);
                            var completed = frame_bridge.finish ();
                            last_texture = completed;
                            needs_frame = false;
                            pq_texture_submitted = true;
                        } catch (Error error) {
                            frame_bridge.abort ();
                            throw error;
                        }
                    } catch (IOError.WOULD_BLOCK error) {
                        // Keep the previous frame and retry on the next libmpv update.
                        // Never spin the GTK snapshot loop when the compositor is slow.
                        needs_frame = true;
                    } catch (Error error) {
                        report_failure (error.message);
                    }
                }
            }
            if (last_texture != null) {
                Graphene.Rect bounds = Graphene.Rect ();
                bounds.init (0, 0, (float) get_width (), (float) get_height ());
                snapshot.append_texture (last_texture, bounds);
            }
        }

        /** Tears down an old engine before the widget attaches a new renderer. */
        private void reconnect_renderer () {
            release_renderer ();
            render_failed = false;
            needs_frame = true;
            pq_texture_submitted = false;
            setup_renderer ();
            queue_draw ();
        }

        /** Attaches only experimental PQ sources to a patched gpu-next renderer. */
        private void setup_renderer () {
            if (!get_realized () || gl_context == null || output != null ||
                current_session == null || current_session.source == null) {
                return;
            }
            if (current_session.color_output_target !=
                MediaKit.ColorOutputTarget.EXPERIMENTAL_BT2020_PQ) {
                report_failure ("HDR view requires EXPERIMENTAL_PQ_TEXTURE playback policy");
                return;
            }
            try {
                gl_context.make_current ();
                output = current_session.create_experimental_gpu_next_output ();
                weak HdrMediaView weak_self = this;
                frame_handler = output.update_requested.connect (() => {
                    if (weak_self != null && !weak_self.render_failed) {
                        weak_self.needs_frame = true;
                        weak_self.queue_draw ();
                    }
                });
                needs_frame = true;
                queue_draw ();
            } catch (Error error) {
                report_failure (error.message);
            }
        }

        /** Detaches GPU objects under the correct context and forgets stale frames. */
        private void release_renderer () {
            if (output != null) {
                if (frame_handler != 0) {
                    SignalHandler.disconnect (output, frame_handler);
                    frame_handler = 0;
                }
                gl_context?.make_current ();
                output.detach ();
                output = null;
            }
            last_texture = null;
            last_width_px = 0;
            last_height_px = 0;
            pq_texture_submitted = false;
        }

        /** Retires the previous playback session observer. */
        private void disconnect_session () {
            if (current_session != null && session_handler != 0) {
                SignalHandler.disconnect (current_session, session_handler);
                session_handler = 0;
            }
            release_renderer ();
        }

        /** Publishes a single error and prevents an unsupported automatic fallback. */
        private void report_failure (string message) {
            if (!render_failed) {
                render_failed = true;
                last_texture = null;
                pq_texture_submitted = false;
                warning ("Experimental HDR rendering failed: %s", message);
                rendering_failed (message);
            }
        }

        /** Releases native resources while GTK still owns a valid widget context. */
        protected override void dispose () {
            disconnect_session ();
            current_session = null;
            base.dispose ();
        }
    }
}
