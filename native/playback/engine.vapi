[CCode (cheader_filename = "engine-adapter.h")]
namespace MediaKitNative {
    /** Private GObject binding for the libmpv-backed engine's GLib contract. */
    [CCode (cname = "MediaKitEngine", type_id = "mediakit_engine_get_type ()",
            lower_case_cprefix = "mediakit_engine_")]
    internal class Engine : GLib.Object {
        /** Creates one independently initialized native playback instance. */
        [CCode (cname = "mediakit_engine_new")]
        public Engine ();

        /** Resolves after an actual native file-loaded or error event. */
        public async bool load_async (string uri, GLib.Cancellable? cancellable = null)
                                      throws GLib.Error;

        /** Resumes native media playback. */
        public bool play () throws GLib.Error;

        /** Pauses native media playback. */
        public bool pause () throws GLib.Error;

        /** Rewinds and pauses without unloading the selected source. */
        public bool stop () throws GLib.Error;

        /** Requests an absolute microsecond seek. */
        public bool seek (int64 position_us) throws GLib.Error;

        /** Cancels outstanding operations and stops the active source. */
        public void close ();

        /** Creates one renderer from the current OpenGL context. */
        public Renderer create_renderer () throws GLib.Error;

        /** Delivered when an actual natural end-of-file occurs. */
        public signal void ended ();

        /** Delivered when the native engine identifies a runtime failure. */
        public signal void failed (string message);

        /** Delivered when a libmpv pause property changes. */
        public signal void pause_changed (bool paused);

        /** Delivered as a bounded-rate current playback position. */
        public signal void position_changed (int64 position_us);

        /** Delivered when a native duration property changes. */
        public signal void duration_changed (int64 duration_us);
    }

    /** Private renderer binding; owning GtkGLArea context is mandatory. */
    [CCode (cname = "MediaKitRenderer", type_id = "mediakit_renderer_get_type ()",
            lower_case_cprefix = "mediakit_renderer_")]
    internal class Renderer : GLib.Object {
        /** Draws a video frame into the current framebuffer. */
        public bool render (int width_px, int height_px) throws GLib.Error;

        /** Releases GPU objects with the same OpenGL context current. */
        public void release ();

        /** Requests a redraw when new video frames become available. */
        public signal void update_requested ();
    }
}
