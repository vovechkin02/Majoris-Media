[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Scoped, authenticated-by-filesystem JSON IPC for the process-owned mpv socket. */
    internal sealed class GpuNextIpc : Object {
        /** Maximum acceptable response line length in bytes. */
        private const size_t MAX_RESPONSE_BYTES = 65536;

        /** Path within a unique, private temporary directory. */
        private string socket_path;

        /** Constructs a transport without opening any socket or blocking the caller. */
        internal GpuNextIpc (string socket_path) {
            Object ();
            this.socket_path = socket_path;
        }

        /** Sends one validated command and returns a copied JSON response data node. */
        internal async Json.Node request_async (string operation, string? text_argument = null,
                                                double? numeric_argument = null,
                                                string? modifier = null,
                                                bool? boolean_argument = null,
                                                Cancellable? cancellable = null) throws Error {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("command");
            builder.begin_array ();
            builder.add_string_value (operation);
            if (text_argument != null) {
                builder.add_string_value (text_argument);
            }
            if (numeric_argument != null) {
                builder.add_double_value ((double) numeric_argument);
            }
            if (modifier != null) {
                builder.add_string_value (modifier);
            }
            if (boolean_argument != null) {
                builder.add_boolean_value ((bool) boolean_argument);
            }
            builder.end_array ();
            builder.set_member_name ("request_id");
            // One distinct private connection is opened for every operation.
            builder.add_int_value (1);
            builder.end_object ();
            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            var message = generator.to_data (null) + "\n";
            var operation_cancel = new Cancellable ();
            ulong cancel_handler_id = 0;
            if (cancellable != null) {
                cancel_handler_id = cancellable.cancelled.connect (() => {
                    operation_cancel.cancel ();
                });
                if (cancellable.is_cancelled ()) {
                    operation_cancel.cancel ();
                }
            }
            bool timed_out = false;
            uint timeout_id = Timeout.add_seconds (5, () => {
                timed_out = true;
                operation_cancel.cancel ();
                return Source.REMOVE;
            });
            try {
                var client = new SocketClient ();
                client.timeout = 5;
                var address = new UnixSocketAddress (socket_path);
                var connection = yield client.connect_async (address, operation_cancel);
                try {
                    size_t bytes_written = 0;
                    // write_all_async handles short writes; the final NUL is not transmitted.
                    uint8[] encoded = message.data[0:message.length];
                    yield connection.output_stream.write_all_async (
                        encoded, Priority.DEFAULT, operation_cancel, out bytes_written
                    );
                    var buffer = new StringBuilder ();
                    int lines_processed = 0;
                    // Read in bounded chunks; read_line_async would allocate before
                    // checking the maximum response length.
                    while (lines_processed < 32) {
                        var chunk = yield connection.input_stream.read_bytes_async (
                            4096, Priority.DEFAULT, operation_cancel
                        );
                        if (chunk.get_size () == 0) {
                            throw new MediaError.PLAYBACK_FAILED (
                                "Advanced player disconnected before its IPC reply"
                            );
                        }
                        unowned uint8[] data = chunk.get_data ();
                        foreach (var byte_value in data) {
                            if (byte_value == 0) {
                                throw new MediaError.PLAYBACK_FAILED (
                                    "Advanced player IPC contained an unexpected NUL"
                                );
                            }
                            buffer.append_c ((char) byte_value);
                        }
                        if (buffer.len > MAX_RESPONSE_BYTES) {
                            throw new MediaError.PLAYBACK_FAILED (
                                "Advanced player IPC response exceeded 64 KiB"
                            );
                        }
                        int newline_position;
                        while ((newline_position = buffer.str.index_of_char ('\n')) >= 0) {
                            var line = buffer.str.substring (0, newline_position);
                            buffer.erase (0, newline_position + 1);
                            lines_processed++;
                            var parser = new Json.Parser ();
                            parser.load_from_data (line, -1);
                            var root = parser.get_root ();
                            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                                throw new MediaError.PLAYBACK_FAILED (
                                    "Advanced player returned invalid JSON"
                                );
                            }
                            var reply = root.get_object ();
                            if (!reply.has_member ("request_id") ||
                                reply.get_int_member ("request_id") != 1) {
                                continue;
                            }
                            if (!reply.has_member ("error") ||
                                reply.get_string_member ("error") != "success") {
                                throw new MediaError.PLAYBACK_FAILED (
                                    "Advanced player rejected the operation: %s".printf (operation)
                                );
                            }
                            var reply_data = reply.get_member ("data");
                            return reply_data != null
                                ? reply_data.copy () : new Json.Node (Json.NodeType.NULL);
                        }
                    }
                    throw new MediaError.PLAYBACK_FAILED (
                        "Advanced player sent too many unsolicited IPC events"
                    );
                } finally {
                    try {
                        connection.close (null);
                    } catch (Error error) {
                        // The already-finished private connection is closed best effort.
                    }
                }
            } catch (IOError.CANCELLED error) {
                if (timed_out) {
                    throw new MediaError.ENGINE_UNAVAILABLE (
                        "Advanced player IPC operation exceeded five seconds"
                    );
                }
                throw error;
            } finally {
                if (timeout_id != 0 && !timed_out) {
                    Source.remove (timeout_id);
                }
                if (cancellable != null && cancel_handler_id != 0) {
                    SignalHandler.disconnect (cancellable, cancel_handler_id);
                }
            }
        }
    }
}
