[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** An immutable GIO-backed source reference; no I/O is performed by construction. */
    public sealed class MediaSource : Object {
        /** GIO file retained for the lifetime of this source object. */
        public File file { get; construct; }

        /** Classifies a local file versus an allowed HTTP(S) source. */
        public SourceKind kind { get; construct; }

        /** Optical-disc identity, kept independent of engine-specific URL syntax. */
        public DiscKind disc_kind { get; construct; default = DiscKind.NONE; }

        /** Requested initial disc navigation mode, not a decoder capability. */
        public DiscStartMode disc_start { get; construct; default = DiscStartMode.LONGEST; }

        /** Explicit disc title index or Blu-ray MPLS playlist number. */
        public uint disc_selection { get; construct; default = 0; }

        /** Whether source parsing is deferred to the native optical-disc engine. */
        public bool is_disc {
            get {
                return disc_kind != DiscKind.NONE;
            }
        }

        /** Canonical GIO URI used for source identity and diagnostics. */
        public string uri {
            owned get {
                return file.get_uri ();
            }
        }

        /** Wraps a local file path without opening or decoding it. */
        public MediaSource.for_path (string path) throws MediaError {
            Object (file: create_local_file (path), kind: SourceKind.LOCAL_FILE);
        }

        /** Accepts file, HTTP, or HTTPS URIs; unsupported schemes are rejected. */
        public MediaSource.for_uri (string uri) throws MediaError {
            Object (file: create_uri_file (uri), kind: classify_uri (uri));
        }

        /** Opens a standalone local TS/MTS/M2TS file without any disc navigation. */
        public MediaSource.for_transport_stream (string path) throws MediaError {
            Object (file: create_local_file (path), kind: SourceKind.TRANSPORT_STREAM);
        }

        /** Describes a local disc drive, BDMV/VIDEO_TS directory, or disc ISO. */
        public MediaSource.for_disc (string path, DiscKind disc_kind,
                                     DiscStartMode start = DiscStartMode.LONGEST,
                                     uint selection = 0) throws MediaError {
            Object (
                file: create_disc_file (path),
                kind: kind_for_disc (disc_kind, start, selection),
                disc_kind: disc_kind,
                disc_start: start,
                disc_selection: selection
            );
        }

        /** Requires a local absolute disc path before any native engine is started. */
        private static File create_disc_file (string path) throws MediaError {
            if (!Path.is_absolute (path) || path.length > 4096 || !path.validate ()) {
                throw new MediaError.INVALID_SOURCE (
                    "Disc device, directory or ISO must use an absolute UTF-8 path"
                );
            }
            return File.new_for_path (path);
        }

        /** Validates the disc type and title/playlist selection without opening the media. */
        private static SourceKind kind_for_disc (DiscKind disc_kind,
                                                  DiscStartMode start,
                                                  uint selection) throws MediaError {
            if (disc_kind != DiscKind.DVD && disc_kind != DiscKind.BLURAY) {
                throw new MediaError.INVALID_SOURCE ("A supported DVD/Blu-ray kind is required");
            }
            if (start == DiscStartMode.PLAYLIST && disc_kind != DiscKind.BLURAY) {
                throw new MediaError.INVALID_ARGUMENT ("MPLS playlists require Blu-ray");
            }
            if (start == DiscStartMode.PLAYLIST && selection > 99999) {
                throw new MediaError.INVALID_ARGUMENT ("MPLS playlist number exceeds 99999");
            }
            if (start != DiscStartMode.TITLE && start != DiscStartMode.PLAYLIST &&
                selection != 0) {
                throw new MediaError.INVALID_ARGUMENT ("Unexpected explicit disc selection");
            }
            return disc_kind == DiscKind.DVD
                ? SourceKind.DVD_DISC : SourceKind.BLURAY_DISC;
        }

        /** Provides the backend URL while keeping absolute device paths separate. */
        internal string engine_uri () {
            if (!is_disc) {
                return uri;
            }
            string prefix = disc_kind == DiscKind.DVD ? "dvd://" : "bd://";
            switch (disc_start) {
            case DiscStartMode.FIRST:
                return prefix + "first";
            case DiscStartMode.MENU:
                return prefix + "menu";
            case DiscStartMode.TITLE:
                return prefix + disc_selection.to_string ();
            case DiscStartMode.PLAYLIST:
                return "bd://mpls/%05u".printf (disc_selection);
            default:
                return prefix + "longest";
            }
        }

        /** Validates a local path before creating a side-effect-free GIO reference. */
        private static File create_local_file (string path) throws MediaError {
            if (path.strip ().length == 0) {
                throw new MediaError.INVALID_SOURCE ("A media file path must not be empty");
            }
            return File.new_for_path (path);
        }

        /** Validates URI schemes before delegating identity creation to GIO. */
        private static File create_uri_file (string uri) throws MediaError {
            var scheme = Uri.parse_scheme (uri);
            if (scheme == null) {
                throw new MediaError.INVALID_SOURCE ("A media URI requires a valid scheme");
            }

            var normalized = scheme.down ();
            if (normalized != "file" && normalized != "http" && normalized != "https") {
                throw new MediaError.INVALID_SOURCE (
                    "Unsupported media URI scheme: %s".printf (scheme)
                );
            }

            return File.new_for_uri (uri);
        }

        /** Classifies a syntactically valid URI without making a network request. */
        private static SourceKind classify_uri (string uri) {
            var scheme = Uri.parse_scheme (uri);
            return scheme != null && scheme.down () == "file"
                ? SourceKind.LOCAL_FILE : SourceKind.NETWORK;
        }
    }
}
