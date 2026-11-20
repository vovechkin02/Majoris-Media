[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** An immutable GIO-backed source reference; no I/O is performed by construction. */
    public sealed class MediaSource : Object {
        /** GIO file retained for the lifetime of this source object. */
        public File file { get; construct; }

        /** Classifies a local file versus an allowed HTTP(S) source. */
        public SourceKind kind { get; construct; }

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
