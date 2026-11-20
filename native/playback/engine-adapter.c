#include "engine-adapter.h"

/** Returns FALSE to prevent Stage 1 from misrepresenting playback support. */
gboolean
mediakit_engine_is_available(void)
{
    return FALSE;
}

/** Returns the stable diagnostic for playback operations before Stage 2. */
const gchar *
mediakit_engine_unavailable_reason(void)
{
    return "The playback engine has not been integrated (Stage 1 architecture only)";
}
