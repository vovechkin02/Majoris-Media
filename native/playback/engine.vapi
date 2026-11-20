[CCode (cheader_filename = "engine-adapter.h")]
namespace MediaKitNative {
    /** Private GObject binding for the libmpv-backed engine's GLib contract. */
    [CCode (cname = "MediaKitEngine", type_id = "mediakit_engine_get_type ()",
            lower_case_cprefix = "mediakit_engine_")]
    internal class Engine : GLib.Object {
        /** Creates one independently initialized native playback instance. */
        [CCode (cname = "mediakit_engine_new")]
        public Engine ();

        /** Initializes libmpv with an explicit audio route and safe codec allowlist. */
        [CCode (cname = "mediakit_engine_new_with_audio")]
        public Engine.with_audio (string device_id, string codecs,
                                  string pcm_channels);

        /** Actual source/decoder and output audio parameters, never receiver capabilities. */
        public GLib.Variant get_audio_information ();

        /** Enumerated mpv audio output endpoints without advertised codec support. */
        public GLib.Variant get_audio_devices ();

        /** Requests a new device and reports eventual failure asynchronously. */
        public bool select_audio_device (string device_id) throws GLib.Error;

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

        /** Returns a structured track-list snapshot, not a human-readable log. */
        public GLib.Variant get_tracks ();

        /** Returns structured chapter metadata in source order. */
        public GLib.Variant get_chapters ();

        /** Returns source color metadata as a{sv}, independent of display output. */
        public GLib.Variant get_video_color ();

        /** Queues video, audio or subtitle selection, with null meaning off. */
        public bool select_track (string kind, string? id) throws GLib.Error;

        /** Queues navigation to the specified zero-based chapter. */
        public bool select_chapter (uint index) throws GLib.Error;

        /** Requests subtitle rendering visibility without losing track selection. */
        public bool set_subtitles_visible (bool visible) throws GLib.Error;

        /** Cancels outstanding operations and stops the active source. */
        public void close ();

        /** Creates one renderer from the current OpenGL context. */
        public Renderer create_renderer () throws GLib.Error;

        /** Delivered when stream or output audio properties change. */
        public signal void audio_metadata_changed ();

        /** Delivered on changes to the engine's enumerated output devices. */
        public signal void audio_devices_changed ();

        /** Delivered after an observed video color-property change. */
        public signal void color_metadata_changed ();

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

        /** Signals a change in track or chapter metadata or selection. */
        public signal void metadata_changed ();

        /** Reports cache pause and percent, with -1 meaning unknown. */
        public signal void buffering_changed (bool active, int percent);

        /** Reports a decoder seek or resynchronization in progress. */
        public signal void seeking_changed (bool active);

        /** Reports actual selected chapter, -1 when unavailable. */
        public signal void chapter_changed (int index);

        /** Reports actual subtitle visibility property. */
        public signal void subtitle_visibility_changed (bool visible);

        /** A nonterminal asynchronous control-command failure. */
        public signal void operation_failed (string message);

        /** Observed active video hardware decoder, or `no` for software. */
        public signal void video_decoder_changed (string decoder);
    }

    /** Private renderer binding; owning GtkGLArea context is mandatory. */
    [CCode (cname = "MediaKitRenderer", type_id = "mediakit_renderer_get_type ()",
            lower_case_cprefix = "mediakit_renderer_")]
    internal class Renderer : GLib.Object {
        /** Draws a video frame into the current framebuffer. */
        public bool render (int width_px, int height_px) throws GLib.Error;

        /** Applies a validated host-provided display ICC profile on its GL thread. */
        public bool set_icc_profile (GLib.Bytes? profile) throws GLib.Error;

        /** Releases GPU objects with the same OpenGL context current. */
        public void release ();

        /** Requests a redraw when new video frames become available. */
        public signal void update_requested ();
    }
}
