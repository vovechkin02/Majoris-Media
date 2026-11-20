[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Determines which standalone Wayland colorspace-hint behavior is requested. */
    public enum GpuNextColorHintMode {
        /** Negotiate the actual output target rather than assuming source passthrough. */
        TARGET,
        /** Request source colorspace signaling; requires downstream color management. */
        SOURCE,
        /** Experimental scene-varying HDR10 hints, not native HDR10+ metadata. */
        SOURCE_DYNAMIC
    }

    /** Validated configuration for a separate mpv gpu-next Wayland window. */
    public sealed class GpuNextLaunchOptions : Object {
        /** Preferred output signaling behavior; dynamic mode remains experimental. */
        public GpuNextColorHintMode color_hint_mode {
            get;
            set;
            default = GpuNextColorHintMode.TARGET;
        }

        /** Network sources require a conscious host opt-in. */
        public bool allow_network { get; set; default = false; }

        /** Uses bounded fixed arguments and a literal argument terminator for the source. */
        public string[] build_arguments (string executable, MediaSource source) throws Error {
            if (executable.strip ().length == 0 || executable != executable.strip ()) {
                throw new MediaError.INVALID_ARGUMENT ("A resolved mpv executable is required");
            }
            if (source.is_disc) {
                throw new MediaError.UNSUPPORTED (
                    "Advanced standalone disc routing is not implemented; use MediaSession"
                );
            }
            if (source.kind == SourceKind.NETWORK && !allow_network) {
                throw new MediaError.INVALID_SOURCE (
                    "Network playback is disabled for the standalone advanced renderer"
                );
            }
            string hint_mode;
            switch (color_hint_mode) {
            case GpuNextColorHintMode.TARGET:
                hint_mode = "target";
                break;
            case GpuNextColorHintMode.SOURCE:
                hint_mode = "source";
                break;
            case GpuNextColorHintMode.SOURCE_DYNAMIC:
                hint_mode = "source-dynamic";
                break;
            default:
                throw new MediaError.INVALID_ARGUMENT ("Invalid color hint mode");
            }
            var location = source.kind == SourceKind.NETWORK
                ? source.uri : source.file.get_path ();
            if (location == null || location.length == 0) {
                throw new MediaError.INVALID_SOURCE ("Source cannot be opened by external mpv");
            }
            return {
                executable,
                "--no-config",
                "--vo=gpu-next",
                "--gpu-context=waylandvk,wayland",
                "--hwdec=auto-safe",
                "--target-colorspace-hint=auto",
                "--target-colorspace-hint-mode=" + hint_mode,
                "--",
                location
            };
        }
    }
}
