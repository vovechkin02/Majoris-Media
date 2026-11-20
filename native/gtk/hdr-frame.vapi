[CCode (cheader_filename = "hdr-frame.h")]
namespace MediaKitGtkNative {
    /** Private bridge from a float GL framebuffer to a BT.2100/PQ GdkTexture. */
    [Compact]
    [CCode (cname = "MediaKitHdrFrame", free_function = "mediakit_hdr_frame_free",
            lower_case_cprefix = "mediakit_hdr_frame_")]
    internal class HdrFrame {
        /** Retains the owning GDK GL context. */
        [CCode (cname = "mediakit_hdr_frame_new")]
        public HdrFrame (Gdk.GLContext context);

        /** Binds a temporary RGBA16F framebuffer for rendering. */
        public bool begin (int width_px, int height_px) throws GLib.Error;

        /** Publishes an immutable PQ-tagged texture with independent GL ownership. */
        public Gdk.Texture finish () throws GLib.Error;

        /** Discards an unfinished frame and restores the previous GL framebuffer. */
        public void abort ();
    }
}
