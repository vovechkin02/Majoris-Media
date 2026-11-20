[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Describes a candidate standalone gpu-next execution environment, not a tested display. */
    public sealed class GpuNextCapabilities : Object {
        /** mpv executable resolved by the host search path. */
        public string executable { get; construct; default = ""; }

        /** Reported version string, or an empty string when version probing failed. */
        public string version { get; construct; default = ""; }

        /** Whether the detected executable is known to meet the mpv 0.42 minimum. */
        public bool compatible_version { get; construct; default = false; }

        /** Whether a Wayland session socket is advertised in the environment. */
        public bool wayland_session { get; construct; default = false; }

        /** A verified Wayland HDR output cannot be inferred from the process environment. */
        public CapabilityStatus native_hdr { get; construct; default = CapabilityStatus.UNVERIFIED; }

        /** The stable libmpv OpenGL render API does not provide gpu-next embedding. */
        public CapabilityStatus embedded_gpu_next { get; construct; default = CapabilityStatus.UNAVAILABLE; }

        /** A compatible mpv can attempt FEL reconstruction, but source/display need testing. */
        public CapabilityStatus dolby_vision_fel {
            get;
            construct;
            default = CapabilityStatus.UNAVAILABLE;
        }

        /** Dynamic luminance hints are not the full HDR10+ metadata protocol. */
        public CapabilityStatus hdr10_plus_metadata_output {
            get;
            construct;
            default = CapabilityStatus.UNAVAILABLE;
        }

        /** True when the standalone renderer can be attempted, not when HDR is confirmed. */
        public bool can_launch {
            get {
                return executable.length > 0 && compatible_version && wayland_session;
            }
        }

        /** Initializes an unavailable snapshot before any executable has been inspected. */
        public GpuNextCapabilities () {
            Object (executable: "", version: "");
        }

        /** Produces a truthful runtime candidate from version output and session identity. */
        public GpuNextCapabilities.from_probe (string executable,
                                               string version_output,
                                               bool wayland_session) {
            int major = -1;
            int minor = -1;
            string version = "";
            foreach (var line in version_output.split ("\n")) {
                if (!line.has_prefix ("mpv ")) {
                    continue;
                }
                var words = line.substring (4).strip ().split (" ");
                if (words.length == 0) {
                    break;
                }
                version = words[0];
                var numeric_version = version.has_prefix ("v")
                    ? version.substring (1) : version;
                var components = numeric_version.split (".");
                if (components.length >= 2 && int.try_parse (components[0], out major) &&
                    int.try_parse (components[1], out minor)) {
                    break;
                }
                major = -1;
                minor = -1;
                break;
            }
            Object (
                executable: executable,
                version: version,
                compatible_version: major > 0 || (major == 0 && minor >= 42),
                wayland_session: wayland_session,
                native_hdr: wayland_session && (major > 0 || (major == 0 && minor >= 42))
                    ? CapabilityStatus.UNVERIFIED : CapabilityStatus.UNAVAILABLE,
                dolby_vision_fel: major > 0 || (major == 0 && minor >= 42)
                    ? CapabilityStatus.UNVERIFIED : CapabilityStatus.UNAVAILABLE
            );
        }
    }
}
