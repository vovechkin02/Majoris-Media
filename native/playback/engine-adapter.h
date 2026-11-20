#ifndef MEDIA_ENGINE_ADAPTER_H
#define MEDIA_ENGINE_ADAPTER_H

#include <glib.h>

G_BEGIN_DECLS

/**
 * mediakit_engine_is_available:
 *
 * Reports whether Stage 1 has an operational playback backend. This
 * deliberately returns FALSE until a real backend has been integrated.
 *
 * Returns: FALSE for this non-playing architecture baseline.
 */
gboolean mediakit_engine_is_available(void);

/**
 * mediakit_engine_unavailable_reason:
 *
 * Returns the diagnostic shared by the unavailable backend adapter.
 *
 * Returns: (transfer none): Static string valid for the process lifetime.
 */
const gchar *mediakit_engine_unavailable_reason(void);

G_END_DECLS

#endif
