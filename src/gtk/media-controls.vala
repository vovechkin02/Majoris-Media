[CCode (gir_namespace = "MediaKitGtk", gir_version = "1.0")]
namespace MediaKitGtk {
    /** Optional GTK4 transport controls connected to an independent MediaSession. */
    [CCode (cname = "MediaKitControls")]
    [GtkTemplate (ui = "/com/majoris/MediaKitGtk/ui/media-controls.ui")]
    public sealed class MediaControls : Gtk.Box {
        /** Playback session that receives transport and seek requests. */
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
                    weak MediaControls weak_owner = this;
                    state_handler_id = current_session.state_changed.connect ((state) => {
                        weak_owner?.update_controls ();
                    });
                    position_handler_id = current_session.position_changed.connect ((value) => {
                        weak_owner?.update_position ();
                    });
                    duration_handler_id = current_session.duration_changed.connect ((value) => {
                        weak_owner?.update_position ();
                    });
                    tracks_handler_id = current_session.tracks_changed.connect (() => {
                        weak_owner?.update_track_menus ();
                    });
                    chapters_handler_id = current_session.chapters_changed.connect (() => {
                        weak_owner?.update_track_menus ();
                    });
                    chapter_handler_id = current_session.chapter_changed.connect ((index) => {
                        weak_owner?.update_track_menus ();
                    });
                    subtitles_handler_id = current_session.subtitle_visibility_changed.connect (
                        (visible) => {
                            weak_owner?.update_track_menus ();
                        }
                    );
                    buffering_handler_id = current_session.buffering_changed.connect (
                        (active, percent) => {
                            weak_owner?.update_position ();
                        }
                    );
                    operation_handler_id = current_session.operation_failed.connect (
                        (message) => {
                            var owner = weak_owner;
                            if (owner != null) {
                                owner.status_label.tooltip_text = message;
                                warning ("Playback control rejected: %s", message);
                            }
                        }
                    );
                }
                update_controls ();
            }
        }

        /** Toggles play/pause, using the session as the only source of truth. */
        [GtkChild]
        private unowned Gtk.Button play_button;

        /** Explicit stop control for the active source. */
        [GtkChild]
        private unowned Gtk.Button stop_button;

        /** Seek position in seconds, converted to microseconds at the core boundary. */
        [GtkChild]
        private unowned Gtk.Scale seek_scale;

        /** Human-readable playback position and duration. */
        [GtkChild]
        private unowned Gtk.Label status_label;

        /** Optional video-stream selector, distinct from the core engine. */
        [GtkChild]
        private unowned Gtk.MenuButton video_menu;

        /** Optional audio-stream selector. */
        [GtkChild]
        private unowned Gtk.MenuButton audio_menu;

        /** Subtitle stream/visibility selector. */
        [GtkChild]
        private unowned Gtk.MenuButton subtitle_menu;

        /** Source chapter navigation menu. */
        [GtkChild]
        private unowned Gtk.MenuButton chapter_menu;

        /** Dynamic stream rows owned by each GTK popover. */
        private Gtk.Box video_list;

        /** Dynamic audio stream rows. */
        private Gtk.Box audio_list;

        /** Dynamic subtitle stream and visibility rows. */
        private Gtk.Box subtitle_list;

        /** Dynamic source chapter rows. */
        private Gtk.Box chapter_list;

        /** Owned session whose observers are disconnected upon replacement. */
        private MediaKit.MediaSession? current_session;

        /** State-change subscription identifier. */
        private ulong state_handler_id = 0;

        /** Position-change subscription identifier. */
        private ulong position_handler_id = 0;

        /** Duration-change subscription identifier. */
        private ulong duration_handler_id = 0;

        /** Subscription for source stream changes. */
        private ulong tracks_handler_id = 0;

        /** Subscription for chapter-list changes. */
        private ulong chapters_handler_id = 0;

        /** Subscription for active chapter navigation. */
        private ulong chapter_handler_id = 0;

        /** Subscription for actual subtitle display state. */
        private ulong subtitles_handler_id = 0;

        /** Subscription for buffered playback status. */
        private ulong buffering_handler_id = 0;

        /** Subscription for nonfatal operation rejection. */
        private ulong operation_handler_id = 0;

        /** Prevents a programmatic slider update from scheduling an unnecessary seek. */
        private bool updating_position = false;

        /** One short debounce timer for mouse/keyboard seek requests. */
        private uint seek_timeout_id = 0;

        /** Creates a neutral XML template-backed transport bar. */
        public MediaControls () {
            Object ();
        }

        /** Wires GTK controls without introducing application-specific styling. */
        construct {
            weak MediaControls weak_owner = this;
            play_button.clicked.connect (() => {
                weak_owner?.on_play_clicked ();
            });
            stop_button.clicked.connect (() => {
                weak_owner?.on_stop_clicked ();
            });
            seek_scale.value_changed.connect (() => {
                weak_owner?.on_seek_value_changed ();
            });
            video_list = configure_popover (video_menu);
            audio_list = configure_popover (audio_menu);
            subtitle_list = configure_popover (subtitle_menu);
            chapter_list = configure_popover (chapter_menu);
            update_controls ();
        }

        /** Submits the appropriate play or pause operation and displays real errors. */
        private void on_play_clicked () {
            if (current_session == null) {
                return;
            }
            try {
                if (current_session.state == MediaKit.PlaybackState.PLAYING) {
                    current_session.pause ();
                } else {
                    current_session.play ();
                }
            } catch (Error error) {
                status_label.label = error.message;
            }
        }

        /** Stops the stream when the session has an active source. */
        private void on_stop_clicked () {
            if (current_session == null) {
                return;
            }
            try {
                current_session.stop ();
            } catch (Error error) {
                status_label.label = error.message;
            }
        }

        /** Debounces user slider requests rather than seeking every intermediate pixel. */
        private void on_seek_value_changed () {
            if (updating_position || current_session == null) {
                return;
            }
            if (seek_timeout_id != 0) {
                Source.remove (seek_timeout_id);
            }
            seek_timeout_id = Timeout.add (150, () => {
                seek_timeout_id = 0;
                if (current_session == null) {
                    return Source.REMOVE;
                }
                try {
                    int64 target_us = (int64) (seek_scale.get_value () * 1000000.0);
                    current_session.seek (target_us);
                } catch (Error error) {
                    status_label.label = error.message;
                }
                return Source.REMOVE;
            });
        }

        /** Applies control state and descriptive button accessibility text. */
        private void update_controls () {
            var state = current_session == null
                ? MediaKit.PlaybackState.EMPTY : current_session.state;
            bool playable = state == MediaKit.PlaybackState.READY ||
                state == MediaKit.PlaybackState.PLAYING ||
                state == MediaKit.PlaybackState.PAUSED ||
                state == MediaKit.PlaybackState.STOPPED ||
                state == MediaKit.PlaybackState.ENDED;
            play_button.sensitive = playable;
            stop_button.sensitive = state == MediaKit.PlaybackState.PLAYING ||
                state == MediaKit.PlaybackState.PAUSED ||
                state == MediaKit.PlaybackState.READY;
            play_button.icon_name = state == MediaKit.PlaybackState.PLAYING
                ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            play_button.tooltip_text = state == MediaKit.PlaybackState.PLAYING
                ? "Pause" : "Play";
            update_position ();
            update_track_menus ();
        }

        /** Synchronizes slider and time display without causing a seek feedback loop. */
        private void update_position () {
            int64 duration_us = current_session == null ? 0 : current_session.duration_us;
            int64 position_us = current_session == null ? 0 : current_session.position_us;
            updating_position = true;
            seek_scale.sensitive = duration_us > 0 && current_session != null &&
                current_session.state != MediaKit.PlaybackState.OPENING &&
                current_session.state != MediaKit.PlaybackState.ERROR;
            seek_scale.set_range (0.0, duration_us > 0 ? duration_us / 1000000.0 : 1.0);
            seek_scale.set_value (position_us / 1000000.0);
            updating_position = false;
            string clock = "%s / %s".printf (
                format_time (position_us), format_time (duration_us)
            );
            if (current_session != null && current_session.is_buffering) {
                int percent = current_session.buffering_percent;
                status_label.label = percent >= 0
                    ? "Buffering %d%% · %s".printf (percent, clock)
                    : "Buffering · %s".printf (clock);
            } else {
                status_label.label = clock;
            }
        }

        /** Converts a microsecond timestamp into readable hours and minutes. */
        private static string format_time (int64 time_us) {
            int64 seconds = time_us > 0 ? time_us / 1000000 : 0;
            int64 minutes = seconds / 60;
            if (minutes >= 60) {
                return "%02d:%02d:%02d".printf (
                    (int) (minutes / 60), (int) (minutes % 60), (int) (seconds % 60)
                );
            }
            return "%02d:%02d".printf ((int) minutes, (int) (seconds % 60));
        }

        /** Creates a neutral GTK popover without application-specific CSS. */
        private static Gtk.Box configure_popover (Gtk.MenuButton button) {
            var popover = new Gtk.Popover ();
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            content.set_margin_top (8);
            content.set_margin_bottom (8);
            content.set_margin_start (8);
            content.set_margin_end (8);
            popover.set_child (content);
            button.set_popover (popover);
            return content;
        }

        /** Removes previous ephemeral chooser rows without retaining callbacks. */
        private static void clear_rows (Gtk.Box container) {
            while (container.get_first_child () != null) {
                container.remove (container.get_first_child ());
            }
        }

        /** Provides a readable stream label without reliance on backend UI strings. */
        private static string track_label (MediaKit.MediaTrack track) {
            string caption = track.title;
            if (caption == "") {
                caption = track.language != "" ? track.language : track.codec;
            }
            if (caption == "") {
                caption = "Track %s".printf (track.id);
            }
            if (track.language != "" && caption != track.language) {
                caption += " (%s)".printf (track.language);
            }
            if (track.forced) {
                caption += " · Forced";
            }
            return caption;
        }

        /** Populates one radio-style stream chooser based on Core track descriptors. */
        private void populate_tracks (Gtk.Box container, MediaKit.TrackKind kind) {
            clear_rows (container);
            if (current_session == null) {
                return;
            }
            Gtk.CheckButton? first = null;
            bool any = false;
            for (uint index = 0; index < current_session.tracks.get_n_items (); index++) {
                var track = (MediaKit.MediaTrack) current_session.tracks.get_item (index);
                if (track.kind != kind) {
                    continue;
                }
                any = true;
                string track_id = track.id;
                var choice = new Gtk.CheckButton.with_label (track_label (track));
                if (first == null) {
                    first = choice;
                } else {
                    choice.set_group (first);
                }
                choice.set_active (track.selected);
                weak Gtk.CheckButton weak_choice = choice;
                weak MediaControls weak_owner = this;
                choice.toggled.connect (() => {
                    var owner = weak_owner;
                    var selected = weak_choice;
                    if (owner != null && selected != null && selected.get_active () &&
                        owner.current_session != null) {
                        try {
                            owner.current_session.select_track (kind, track_id);
                        } catch (Error error) {
                            owner.status_label.tooltip_text = error.message;
                        }
                    }
                });
                container.append (choice);
            }
            if (!any) {
                var none = new Gtk.Label ("No tracks available");
                none.set_xalign (0);
                container.append (none);
            }
            if (kind == MediaKit.TrackKind.SUBTITLE) {
                var off = new Gtk.CheckButton.with_label ("Off");
                if (first != null) {
                    off.set_group (first);
                }
                off.set_active (
                    current_session.selected_track_id (MediaKit.TrackKind.SUBTITLE) == null
                );
                weak Gtk.CheckButton weak_off = off;
                weak MediaControls weak_owner = this;
                off.toggled.connect (() => {
                    var owner = weak_owner;
                    var selected = weak_off;
                    if (owner != null && selected != null && selected.get_active () &&
                        owner.current_session != null) {
                        try {
                            owner.current_session.select_subtitle_track (null);
                        } catch (Error error) {
                            owner.status_label.tooltip_text = error.message;
                        }
                    }
                });
                container.append (off);
                var visibility = new Gtk.CheckButton.with_label ("Show subtitles");
                visibility.set_active (current_session.subtitles_visible);
                weak Gtk.CheckButton weak_visibility = visibility;
                weak MediaControls weak_visibility_owner = this;
                visibility.toggled.connect (() => {
                    var owner = weak_visibility_owner;
                    var selected = weak_visibility;
                    if (owner != null && selected != null && owner.current_session != null) {
                        try {
                            owner.current_session.set_subtitles_visible (
                                selected.get_active ()
                            );
                        } catch (Error error) {
                            owner.status_label.tooltip_text = error.message;
                        }
                    }
                });
                container.append (visibility);
            }
        }

        /** Rebuilds the current source's chapter chooser with accurate selection. */
        private void populate_chapters () {
            clear_rows (chapter_list);
            if (current_session == null) {
                return;
            }
            Gtk.CheckButton? first = null;
            for (uint index = 0; index < current_session.chapters.get_n_items (); index++) {
                var chapter = (MediaKit.MediaChapter) current_session.chapters.get_item (index);
                uint chapter_index = chapter.index;
                string label = chapter.title != "" ? chapter.title
                    : "Chapter %u".printf (chapter_index + 1);
                var choice = new Gtk.CheckButton.with_label (label);
                if (first == null) {
                    first = choice;
                } else {
                    choice.set_group (first);
                }
                choice.set_active (current_session.current_chapter_index == (int) chapter_index);
                weak Gtk.CheckButton weak_choice = choice;
                weak MediaControls weak_owner = this;
                choice.toggled.connect (() => {
                    var owner = weak_owner;
                    var selected = weak_choice;
                    if (owner != null && selected != null && selected.get_active () &&
                        owner.current_session != null) {
                        try {
                            owner.current_session.select_chapter (chapter_index);
                        } catch (Error error) {
                            owner.status_label.tooltip_text = error.message;
                        }
                    }
                });
                chapter_list.append (choice);
            }
        }

        /** Keeps presentation menus synchronized with actual engine metadata. */
        private void update_track_menus () {
            populate_tracks (video_list, MediaKit.TrackKind.VIDEO);
            populate_tracks (audio_list, MediaKit.TrackKind.AUDIO);
            populate_tracks (subtitle_list, MediaKit.TrackKind.SUBTITLE);
            populate_chapters ();
            bool ready = current_session != null && current_session.source != null &&
                current_session.state != MediaKit.PlaybackState.OPENING &&
                current_session.state != MediaKit.PlaybackState.ERROR;
            uint video_count = 0;
            uint audio_count = 0;
            uint subtitle_count = 0;
            if (current_session != null) {
                for (uint index = 0; index < current_session.tracks.get_n_items (); index++) {
                    var track = (MediaKit.MediaTrack) current_session.tracks.get_item (index);
                    switch (track.kind) {
                    case MediaKit.TrackKind.VIDEO:
                        video_count++;
                        break;
                    case MediaKit.TrackKind.AUDIO:
                        audio_count++;
                        break;
                    case MediaKit.TrackKind.SUBTITLE:
                        subtitle_count++;
                        break;
                    }
                }
            }
            video_menu.sensitive = ready && video_count > 0;
            audio_menu.sensitive = ready && audio_count > 0;
            subtitle_menu.sensitive = ready && subtitle_count > 0;
            chapter_menu.sensitive = ready && current_session != null &&
                current_session.chapters.get_n_items () > 0;
        }

        /** Disconnects old subscriptions and cancels pending debounce on replacement. */
        private void disconnect_session () {
            if (seek_timeout_id != 0) {
                Source.remove (seek_timeout_id);
                seek_timeout_id = 0;
            }
            if (current_session != null) {
                if (state_handler_id != 0) {
                    SignalHandler.disconnect (current_session, state_handler_id);
                    state_handler_id = 0;
                }
                if (position_handler_id != 0) {
                    SignalHandler.disconnect (current_session, position_handler_id);
                    position_handler_id = 0;
                }
                if (duration_handler_id != 0) {
                    SignalHandler.disconnect (current_session, duration_handler_id);
                    duration_handler_id = 0;
                }
                if (tracks_handler_id != 0) {
                    SignalHandler.disconnect (current_session, tracks_handler_id);
                    tracks_handler_id = 0;
                }
                if (chapters_handler_id != 0) {
                    SignalHandler.disconnect (current_session, chapters_handler_id);
                    chapters_handler_id = 0;
                }
                if (chapter_handler_id != 0) {
                    SignalHandler.disconnect (current_session, chapter_handler_id);
                    chapter_handler_id = 0;
                }
                if (subtitles_handler_id != 0) {
                    SignalHandler.disconnect (current_session, subtitles_handler_id);
                    subtitles_handler_id = 0;
                }
                if (buffering_handler_id != 0) {
                    SignalHandler.disconnect (current_session, buffering_handler_id);
                    buffering_handler_id = 0;
                }
                if (operation_handler_id != 0) {
                    SignalHandler.disconnect (current_session, operation_handler_id);
                    operation_handler_id = 0;
                }
            }
            current_session = null;
        }

        /** Cleans up delayed actions and subscriptions during GTK disposal. */
        protected override void dispose () {
            disconnect_session ();
            base.dispose ();
        }
    }
}
