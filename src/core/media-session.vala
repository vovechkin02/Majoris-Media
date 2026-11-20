[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Playback Facade for one media source and its asynchronously managed engine. */
    public sealed class MediaSession : Object {
        /** Current lifecycle state, updated when native operations succeed or fail. */
        public PlaybackState state { get; private set; default = PlaybackState.EMPTY; }

        /** Current source, null before an open or after close. */
        public MediaSource? source { get; private set; }

        /** Latest playback failure; expected cancellations do not set this property. */
        public string? last_error { get; private set; }

        /** Runtime capability snapshot, conservative about untested display paths. */
        public MediaCapabilities capabilities { get; private set; }

        /** Caller-requested output policies, distinct from negotiated capabilities. */
        public PlaybackOptions options { get; construct; }

        /** Last observed playback position in microseconds. */
        public int64 position_us { get; private set; default = 0; }

        /** Last observed duration in microseconds, zero when unknown. */
        public int64 duration_us { get; private set; default = 0; }

        /** Emitted on each real state transition on the owning main context. */
        public signal void state_changed (PlaybackState state);

        /** Emitted before an old OpenGL endpoint must be released or a new one attached. */
        public signal void output_changed ();

        /** Emitted after observed playback position changes. */
        public signal void position_changed (int64 position_us);

        /** Emitted after observed stream duration changes. */
        public signal void duration_changed (int64 duration_us);

        /** Live source tracks; changed models emit normal ListModel notifications. */
        public ListModel tracks {
            get {
                return track_store;
            }
        }

        /** Current chapter descriptors in source order. */
        public ListModel chapters {
            get {
                return chapter_store;
            }
        }

        /** Whether the engine is stalled waiting for cache data. */
        public bool is_buffering { get; private set; default = false; }

        /** Cache fill percentage, -1 if unavailable or not measured. */
        public int buffering_percent { get; private set; default = -1; }

        /** Whether a seek or playback resynchronization is in progress. */
        public bool is_seeking { get; private set; default = false; }

        /** Engine-observed subtitle rendering state, independent of track selection. */
        public bool subtitles_visible { get; private set; default = true; }

        /** Active decoder identifier, `no` for software or empty when unknown. */
        public string active_video_decoder { get; private set; default = ""; }

        /** True only when libmpv reports an actual hardware decoder in use. */
        public bool hardware_decoding_active { get; private set; default = false; }

        /** Emitted on an observed decoder change, including software fallback. */
        public signal void video_decoder_changed (string decoder, bool accelerated);

        /** Current source chapter, or -1 when the engine cannot identify one. */
        public int current_chapter_index { get; private set; default = -1; }

        /** Emitted after live track data or current stream selection changes. */
        public signal void tracks_changed ();

        /** Emitted after live chapter metadata changes. */
        public signal void chapters_changed ();

        /** Emitted when cache pause or fill progress changes. */
        public signal void buffering_changed (bool active, int percent);

        /** Emitted when engine seeking or resynchronization changes. */
        public signal void seeking_changed (bool active);

        /** Emitted after the active chapter changes, -1 when unknown. */
        public signal void chapter_changed (int index);

        /** Emitted after the actual subtitle visibility property changes. */
        public signal void subtitle_visibility_changed (bool visible);

        /** Reports rejected nonfatal control requests without ending playback. */
        public signal void operation_failed (string message);

        /** Internal playback Strategy, never part of the installed public API. */
        private PlaybackBackend backend;

        /** Mutable backing store hidden behind the public read-only track model. */
        private ListStore track_store;

        /** Mutable backing store hidden behind the public read-only chapter model. */
        private ListStore chapter_store;

        /** Owns backend signal connection identifiers for deterministic disconnection. */
        private ulong[] backend_handlers = {};

        /** Unique request counter prevents superseded callbacks from mutating state. */
        private uint64 request_generation = 0;

        /** Retains current cancellable so close/open can cancel an in-flight request. */
        private Cancellable? current_load;

        /** Constructs a lightweight session without initializing libmpv at startup. */
        public MediaSession (PlaybackOptions? options = null) {
            Object (options: options ?? new PlaybackOptions ());
            track_store = new ListStore (typeof (MediaTrack));
            chapter_store = new ListStore (typeof (MediaChapter));
            backend = new UnavailableBackend ();
            attach_backend ();
            capabilities = new MediaCapabilities (
                native_engine_is_available ()
                    ? CapabilityStatus.AVAILABLE : CapabilityStatus.UNAVAILABLE
            );
        }

        /** Loads one validated source asynchronously, resolving after FILE_LOADED. */
        public async void open_async (MediaSource requested_source,
                                      Cancellable? cancellable = null) throws Error {
            cancellable?.set_error_if_cancelled ();
            uint64 generation = ++request_generation;
            cancel_pending ();
            detach_backend ();
            var old_backend = backend;
            backend = create_backend ();
            attach_backend ();
            source = requested_source;
            output_changed ();
            old_backend.close ();
            last_error = null;
            position_us = 0;
            duration_us = 0;
            position_changed (0);
            duration_changed (0);
            reset_live_metadata ();
            var request = new Cancellable ();
            current_load = request;
            ulong cancel_handler_id = 0;
            if (cancellable != null) {
                cancel_handler_id = cancellable.cancelled.connect (() => {
                    request.cancel ();
                });
                if (cancellable.is_cancelled ()) {
                    request.cancel ();
                }
            }
            update_state (PlaybackState.OPENING);

            try {
                yield backend.open_async (requested_source, request);
                if (request.is_cancelled () || generation != request_generation) {
                    throw new IOError.CANCELLED ("Media load was superseded");
                }
                refresh_live_metadata ();
                update_state (PlaybackState.READY);
            } catch (Error error) {
                if (generation == request_generation) {
                    if (error is IOError.CANCELLED) {
                        source = null;
                        last_error = null;
                        reset_live_metadata ();
                        update_state (PlaybackState.EMPTY);
                    } else {
                        last_error = error.message;
                        reset_live_metadata ();
                        update_state (PlaybackState.ERROR);
                    }
                }
                throw error;
            } finally {
                if (cancellable != null && cancel_handler_id != 0) {
                    SignalHandler.disconnect (cancellable, cancel_handler_id);
                }
                if (generation == request_generation) {
                    current_load = null;
                }
            }
        }

        /** Resumes playback after a successful open, pause, stop or natural end. */
        public void play () throws Error {
            if (state != PlaybackState.READY && state != PlaybackState.PAUSED &&
                state != PlaybackState.STOPPED && state != PlaybackState.ENDED) {
                throw new MediaError.INVALID_ARGUMENT ("No ready stream to play");
            }
            if (state == PlaybackState.STOPPED || state == PlaybackState.ENDED) {
                backend.seek (0);
            }
            backend.play ();
            update_state (PlaybackState.PLAYING);
        }

        /** Pauses active playback only when a stream is playing. */
        public void pause () throws Error {
            if (state != PlaybackState.PLAYING) {
                throw new MediaError.INVALID_ARGUMENT ("Playback is not running");
            }
            backend.pause ();
            update_state (PlaybackState.PAUSED);
        }

        /** Stops an active or paused stream while retaining its source. */
        public void stop () throws Error {
            if (state != PlaybackState.PLAYING && state != PlaybackState.PAUSED &&
                state != PlaybackState.READY) {
                throw new MediaError.INVALID_ARGUMENT ("No active stream to stop");
            }
            backend.stop ();
            update_state (PlaybackState.STOPPED);
        }

        /** Seeks to a nonnegative microsecond position in the active stream. */
        public void seek (int64 position_us) throws Error {
            if (position_us < 0) {
                throw new MediaError.INVALID_ARGUMENT ("Seek position must not be negative");
            }
            if (state != PlaybackState.READY && state != PlaybackState.PLAYING &&
                state != PlaybackState.PAUSED && state != PlaybackState.STOPPED &&
                state != PlaybackState.ENDED) {
                throw new MediaError.INVALID_ARGUMENT ("No seekable stream is ready");
            }
            backend.seek (position_us);
        }

        /** Selects a stream by exact ID, or disables that stream when ID is null. */
        public void select_track (TrackKind kind, string? id) throws Error {
            ensure_media_ready ();
            if (id != null && !has_track (kind, id)) {
                throw new MediaError.INVALID_ARGUMENT (
                    "Selected stream is not present in the active source"
                );
            }
            backend.select_track (kind, id);
        }

        /** Requests the source's audio stream without altering subtitle visibility. */
        public void select_audio_track (string? id) throws Error {
            select_track (TrackKind.AUDIO, id);
        }

        /** Requests the selected video stream or disables video with null. */
        public void select_video_track (string? id) throws Error {
            select_track (TrackKind.VIDEO, id);
        }

        /** Requests a subtitle track, or turns subtitle decoding off with null. */
        public void select_subtitle_track (string? id) throws Error {
            select_track (TrackKind.SUBTITLE, id);
        }

        /** Shows or hides selected subtitles without changing which track is selected. */
        public void set_subtitles_visible (bool visible) throws Error {
            ensure_media_ready ();
            backend.set_subtitles_visible (visible);
        }

        /** Navigates to a source chapter using its zero-based index. */
        public void select_chapter (uint index) throws Error {
            ensure_media_ready ();
            bool found = false;
            for (uint position = 0; position < chapter_store.get_n_items (); position++) {
                var chapter = (MediaChapter) chapter_store.get_item (position);
                if (chapter.index == index) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                throw new MediaError.INVALID_ARGUMENT ("Chapter index is out of range");
            }
            backend.select_chapter (index);
        }

        /** Finds the actual selected track ID, or null if the type is disabled. */
        public string? selected_track_id (TrackKind kind) {
            for (uint index = 0; index < track_store.get_n_items (); index++) {
                var track = (MediaTrack) track_store.get_item (index);
                if (track.kind == kind && track.selected) {
                    return track.id;
                }
            }
            return null;
        }

        /** Creates a GL output endpoint for an already initialized active backend. */
        public OpenGlOutput create_opengl_output () throws Error {
            return backend.create_opengl_output ();
        }

        /** Cancels pending work, detaches presentation and empties this session. */
        public void close () {
            ++request_generation;
            cancel_pending ();
            detach_backend ();
            var old_backend = backend;
            backend = new UnavailableBackend ();
            attach_backend ();
            source = null;
            output_changed ();
            old_backend.close ();
            last_error = null;
            position_us = 0;
            duration_us = 0;
            position_changed (0);
            duration_changed (0);
            reset_live_metadata ();
            update_state (PlaybackState.EMPTY);
        }

        /** Creates an operational backend only at the source-open boundary. */
        private static PlaybackBackend create_backend () {
            if (native_engine_is_available ()) {
                return new MpvBackend ();
            }
            return new UnavailableBackend ();
        }

        /** Subscribes to per-engine events and keeps GTK out of the playback core. */
        private void attach_backend () {
            weak MediaSession weak_self = this;
            backend_handlers += backend.ended.connect (() => {
                var owner = weak_self;
                if (owner != null && (owner.state == PlaybackState.PLAYING ||
                                      owner.state == PlaybackState.PAUSED)) {
                    owner.update_state (PlaybackState.ENDED);
                }
            });
            backend_handlers += backend.failed.connect ((message) => {
                var owner = weak_self;
                if (owner != null && owner.state != PlaybackState.EMPTY) {
                    owner.last_error = message;
                    owner.update_state (PlaybackState.ERROR);
                }
            });
            backend_handlers += backend.pause_changed.connect ((paused) => {
                var owner = weak_self;
                if (owner == null) {
                    return;
                }
                if (owner.state == PlaybackState.PLAYING && paused) {
                    owner.update_state (PlaybackState.PAUSED);
                } else if (owner.state == PlaybackState.PAUSED && !paused) {
                    owner.update_state (PlaybackState.PLAYING);
                }
            });
            backend_handlers += backend.position_changed.connect ((value) => {
                var owner = weak_self;
                if (owner != null) {
                    owner.position_us = value;
                    owner.position_changed (value);
                }
            });
            backend_handlers += backend.duration_changed.connect ((value) => {
                var owner = weak_self;
                if (owner != null) {
                    owner.duration_us = value;
                    owner.duration_changed (value);
                }
            });
            backend_handlers += backend.metadata_changed.connect (() => {
                var owner = weak_self;
                if (owner != null && owner.source != null &&
                    owner.state != PlaybackState.EMPTY) {
                    owner.refresh_live_metadata ();
                }
            });
            backend_handlers += backend.buffering_changed.connect ((active, percent) => {
                var owner = weak_self;
                if (owner != null && owner.source != null) {
                    owner.update_buffering (active, percent);
                }
            });
            backend_handlers += backend.seeking_changed.connect ((active) => {
                var owner = weak_self;
                if (owner != null && owner.source != null && owner.is_seeking != active) {
                    owner.is_seeking = active;
                    owner.seeking_changed (active);
                }
            });
            backend_handlers += backend.chapter_changed.connect ((index) => {
                var owner = weak_self;
                if (owner != null && owner.source != null &&
                    owner.current_chapter_index != index) {
                    owner.current_chapter_index = index;
                    owner.chapter_changed (index);
                }
            });
            backend_handlers += backend.subtitle_visibility_changed.connect ((visible) => {
                var owner = weak_self;
                if (owner != null && owner.source != null &&
                    owner.subtitles_visible != visible) {
                    owner.subtitles_visible = visible;
                    owner.subtitle_visibility_changed (visible);
                }
            });
            backend_handlers += backend.operation_failed.connect ((message) => {
                var owner = weak_self;
                if (owner != null && owner.source != null) {
                    owner.last_error = message;
                    owner.operation_failed (message);
                }
            });
            backend_handlers += backend.video_decoder_changed.connect ((decoder) => {
                var owner = weak_self;
                if (owner == null || owner.source == null) {
                    return;
                }
                bool hardware = decoder != "" && decoder != "no";
                if (owner.active_video_decoder != decoder ||
                    owner.hardware_decoding_active != hardware) {
                    owner.active_video_decoder = decoder;
                    owner.hardware_decoding_active = hardware;
                    owner.video_decoder_changed (decoder, hardware);
                }
            });
        }

        /** Decodes one string entry from a typed source metadata dictionary. */
        private static string read_string (Variant item, string key) {
            var field = item.lookup_value (key, new VariantType ("s"));
            return field == null ? "" : field.get_string ();
        }

        /** Reads one Boolean metadata value with a conservative false fallback. */
        private static bool read_flag (Variant item, string key) {
            var field = item.lookup_value (key, new VariantType ("b"));
            return field != null && field.get_boolean ();
        }

        /** Maps the mpv stream token into the public domain enum. */
        private static bool parse_track_kind (string kind_name, out TrackKind kind) {
            switch (kind_name) {
            case "video":
                kind = TrackKind.VIDEO;
                return true;
            case "audio":
                kind = TrackKind.AUDIO;
                return true;
            case "sub":
                kind = TrackKind.SUBTITLE;
                return true;
            default:
                kind = TrackKind.VIDEO;
                return false;
            }
        }

        /** Refreshes read-only public models from native structured source metadata. */
        private void refresh_live_metadata () {
            try {
                var native_tracks = backend.get_tracks ();
                var native_chapters = backend.get_chapters ();
                var next_tracks = new ListStore (typeof (MediaTrack));
                var next_chapters = new ListStore (typeof (MediaChapter));
                for (size_t index = 0; index < native_tracks.n_children (); index++) {
                    var item = native_tracks.get_child_value (index);
                    TrackKind kind;
                    string id = read_string (item, "id");
                    if (id == "" || !parse_track_kind (read_string (item, "type"),
                                                         out kind)) {
                        continue;
                    }
                    next_tracks.append (new MediaTrack (
                        id, kind, read_string (item, "codec"),
                        read_string (item, "lang"), read_string (item, "title"),
                        read_flag (item, "selected"), read_flag (item, "default"),
                        read_flag (item, "forced"), read_flag (item, "external")
                    ));
                }
                for (size_t index = 0; index < native_chapters.n_children (); index++) {
                    var item = native_chapters.get_child_value (index);
                    var index_value = item.lookup_value ("index", new VariantType ("u"));
                    var time_value = item.lookup_value ("start-us", new VariantType ("x"));
                    if (index_value == null || time_value == null) {
                        continue;
                    }
                    next_chapters.append (new MediaChapter (
                        index_value.get_uint32 (), time_value.get_int64 (),
                        read_string (item, "title")
                    ));
                }
                track_store.remove_all ();
                for (uint index = 0; index < next_tracks.get_n_items (); index++) {
                    track_store.append (next_tracks.get_item (index));
                }
                chapter_store.remove_all ();
                for (uint index = 0; index < next_chapters.get_n_items (); index++) {
                    chapter_store.append (next_chapters.get_item (index));
                }
                tracks_changed ();
                chapters_changed ();
            } catch (Error error) {
                warning ("Could not refresh live media metadata: %s", error.message);
            }
        }

        /** Clears per-source models and engine observation without changing options. */
        private void reset_live_metadata () {
            track_store.remove_all ();
            chapter_store.remove_all ();
            tracks_changed ();
            chapters_changed ();
            update_buffering (false, -1);
            if (active_video_decoder != "" || hardware_decoding_active) {
                active_video_decoder = "";
                hardware_decoding_active = false;
                video_decoder_changed ("", false);
            }
            if (is_seeking) {
                is_seeking = false;
                seeking_changed (false);
            }
            if (current_chapter_index != -1) {
                current_chapter_index = -1;
                chapter_changed (-1);
            }
            if (!subtitles_visible) {
                subtitles_visible = true;
                subtitle_visibility_changed (true);
            }
        }

        /** Only changes buffering observers if the reported values differ. */
        private void update_buffering (bool active, int percent) {
            int corrected = percent < 0 ? -1 : (percent > 100 ? 100 : percent);
            if (is_buffering != active || buffering_percent != corrected) {
                is_buffering = active;
                buffering_percent = corrected;
                buffering_changed (active, corrected);
            }
        }

        /** Rejects stream controls before a media file is ready for manipulation. */
        private void ensure_media_ready () throws Error {
            if (source == null || state == PlaybackState.EMPTY ||
                state == PlaybackState.OPENING || state == PlaybackState.ERROR) {
                throw new MediaError.INVALID_ARGUMENT ("No ready stream is loaded");
            }
        }

        /** Checks a requested track against the source's current ID inventory. */
        private bool has_track (TrackKind kind, string id) {
            for (uint index = 0; index < track_store.get_n_items (); index++) {
                var track = (MediaTrack) track_store.get_item (index);
                if (track.kind == kind && track.id == id) {
                    return true;
                }
            }
            return false;
        }

        /** Disconnects the old engine before its request is invalidated. */
        private void detach_backend () {
            foreach (var handler in backend_handlers) {
                SignalHandler.disconnect (backend, handler);
            }
            backend_handlers = {};
        }

        /** Cancels the superseded operation without canceling a caller-owned token. */
        private void cancel_pending () {
            current_load?.cancel ();
            current_load = null;
        }

        /** Emits one notification per effective lifecycle change. */
        private void update_state (PlaybackState next_state) {
            if (state != next_state) {
                state = next_state;
                state_changed (next_state);
            }
        }

        /** Completes source teardown and releases all engine signal subscriptions. */
        protected override void dispose () {
            cancel_pending ();
            output_changed ();
            detach_backend ();
            backend.close ();
            base.dispose ();
        }
    }
}
