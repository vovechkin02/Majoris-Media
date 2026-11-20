[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Headless OpenGL presentation endpoint for one active playback engine. */
    public sealed class OpenGlOutput : Object {
        /** Instructs an attached view to schedule a redraw on its GTK main context. */
        public signal void update_requested ();

        /** Private renderer is never exposed to an application or a GTK widget. */
        private MediaKitNative.Renderer renderer;

        /** Signal listener owned by this output object. */
        private ulong update_handler_id = 0;

        /** Tracks explicit detach calls before the host GL context is lost. */
        private bool detached = false;

        /** Adopts one native renderer after successful GL-context initialization. */
        internal OpenGlOutput (MediaKitNative.Renderer renderer) {
            Object ();
            this.renderer = renderer;
            weak OpenGlOutput weak_self = this;
            update_handler_id = renderer.update_requested.connect (() => {
                if (weak_self != null && !weak_self.detached) {
                    weak_self.update_requested ();
                }
            });
        }

        /** Renders into the currently bound framebuffer; all dimensions are pixels. */
        public void render_current_frame (int width_px, int height_px) throws Error {
            if (detached) {
                throw new MediaError.INVALID_ARGUMENT ("OpenGL output is detached");
            }
            renderer.render (width_px, height_px);
        }

        /** Installs a caller-selected display ICC profile on the current GL thread. */
        public void set_display_icc_profile (Bytes? profile) throws Error {
            if (detached) {
                throw new MediaError.INVALID_ARGUMENT ("OpenGL output is detached");
            }
            renderer.set_icc_profile (profile);
        }

        /** Releases graphics resources before a GLArea loses its current context. */
        public void detach () {
            if (detached) {
                return;
            }
            detached = true;
            if (update_handler_id != 0) {
                SignalHandler.disconnect (renderer, update_handler_id);
                update_handler_id = 0;
            }
            renderer.release ();
        }

        /** Releases an unclosed output when the last reference is disposed. */
        protected override void dispose () {
            detach ();
            base.dispose ();
        }
    }
}
