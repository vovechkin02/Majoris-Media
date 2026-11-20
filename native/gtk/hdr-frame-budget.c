#include "hdr-frame-budget.h"

#include <stdatomic.h>
#include <stdlib.h>

/** A portable C11 refcount is shared by a widget and retired GTK textures. */
struct MediaKitHdrFrameBudget {
    atomic_uint references;
    atomic_uint in_flight;
    unsigned int maximum;
};

/** Creates a bounded accounting record without creating a GL context. */
MediaKitHdrFrameBudget *
mediakit_hdr_frame_budget_new(unsigned int maximum)
{
    if (maximum == 0) {
        return NULL;
    }
    MediaKitHdrFrameBudget *budget = calloc(1, sizeof(*budget));
    if (budget != NULL) {
        atomic_init(&budget->references, 1);
        atomic_init(&budget->in_flight, 0);
        budget->maximum = maximum;
    }
    return budget;
}

/** Retains the tracker without extending the lifetime of the producer. */
MediaKitHdrFrameBudget *
mediakit_hdr_frame_budget_ref(MediaKitHdrFrameBudget *budget)
{
    if (budget == NULL) {
        abort();
    }
    unsigned int previous = atomic_fetch_add_explicit(&budget->references, 1,
                                                      memory_order_relaxed);
    if (previous == 0) {
        abort();
    }
    return budget;
}

/** Frees the tracker once neither the widget nor any released frame owns it. */
void
mediakit_hdr_frame_budget_unref(MediaKitHdrFrameBudget *budget)
{
    if (budget == NULL) {
        return;
    }
    unsigned int previous = atomic_fetch_sub_explicit(&budget->references, 1,
                                                      memory_order_acq_rel);
    if (previous == 0) {
        abort();
    }
    if (previous == 1) {
        if (atomic_load_explicit(&budget->in_flight, memory_order_acquire) != 0) {
            abort();
        }
        free(budget);
    }
}

/** Reserves at most maximum concurrent published or in-progress GPU textures. */
bool
mediakit_hdr_frame_budget_try_acquire(MediaKitHdrFrameBudget *budget)
{
    if (budget == NULL) {
        abort();
    }
    unsigned int current = atomic_load_explicit(&budget->in_flight,
                                                memory_order_relaxed);
    while (current < budget->maximum) {
        if (atomic_compare_exchange_weak_explicit(&budget->in_flight,
                                                   &current, current + 1,
                                                   memory_order_acq_rel,
                                                   memory_order_relaxed)) {
            return true;
        }
    }
    return false;
}

/** Releases a previously reserved slot when an unsubmitted or retired frame dies. */
void
mediakit_hdr_frame_budget_release(MediaKitHdrFrameBudget *budget)
{
    if (budget == NULL) {
        abort();
    }
    unsigned int current = atomic_load_explicit(&budget->in_flight,
                                                memory_order_relaxed);
    while (current != 0) {
        if (atomic_compare_exchange_weak_explicit(&budget->in_flight,
                                                   &current, current - 1,
                                                   memory_order_acq_rel,
                                                   memory_order_relaxed)) {
            return;
        }
    }
    /* A double release would otherwise be silent in NDEBUG release builds. */
    abort();
}

/** Observes the current number of slots retained by frames or their producer. */
unsigned int
mediakit_hdr_frame_budget_in_flight(const MediaKitHdrFrameBudget *budget)
{
    if (budget == NULL) {
        abort();
    }
    return atomic_load_explicit(&budget->in_flight, memory_order_acquire);
}
