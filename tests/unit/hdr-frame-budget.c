#include "hdr-frame-budget.h"

/* Meson release builds may set NDEBUG; test assertions must still execute. */
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stddef.h>
#include <pthread.h>
#include <sched.h>

/** Verifies capacity enforcement, failure recovery and independent texture lifetime. */
static void
test_texture_budget(void)
{
    MediaKitHdrFrameBudget *producer = mediakit_hdr_frame_budget_new(3);
    assert(producer != NULL);
    assert(mediakit_hdr_frame_budget_in_flight(producer) == 0);
    assert(mediakit_hdr_frame_budget_try_acquire(producer));
    assert(mediakit_hdr_frame_budget_try_acquire(producer));
    assert(mediakit_hdr_frame_budget_try_acquire(producer));
    assert(!mediakit_hdr_frame_budget_try_acquire(producer));
    assert(mediakit_hdr_frame_budget_in_flight(producer) == 3);

    /* The texture still owns the tracker after its producing widget is freed. */
    MediaKitHdrFrameBudget *retired = mediakit_hdr_frame_budget_ref(producer);
    mediakit_hdr_frame_budget_unref(producer);
    mediakit_hdr_frame_budget_release(retired);
    assert(mediakit_hdr_frame_budget_try_acquire(retired));
    assert(mediakit_hdr_frame_budget_in_flight(retired) == 3);
    mediakit_hdr_frame_budget_release(retired);
    mediakit_hdr_frame_budget_release(retired);
    mediakit_hdr_frame_budget_release(retired);
    assert(mediakit_hdr_frame_budget_in_flight(retired) == 0);
    mediakit_hdr_frame_budget_unref(retired);
}

/** Tests invalid capacity and single-slot recovery without GPU hardware. */
static void
test_invalid_and_single_slot_budget(void)
{
    assert(mediakit_hdr_frame_budget_new(0) == NULL);
    MediaKitHdrFrameBudget *budget = mediakit_hdr_frame_budget_new(1);
    assert(budget != NULL);
    assert(mediakit_hdr_frame_budget_try_acquire(budget));
    assert(!mediakit_hdr_frame_budget_try_acquire(budget));
    mediakit_hdr_frame_budget_release(budget);
    assert(mediakit_hdr_frame_budget_try_acquire(budget));
    mediakit_hdr_frame_budget_release(budget);
    mediakit_hdr_frame_budget_unref(budget);
}

/** One independent worker attempts many concurrent reservations and releases. */
static void *
exercise_concurrent_budget(void *user_data)
{
    MediaKitHdrFrameBudget *budget = user_data;
    for (unsigned int attempt = 0; attempt < 5000; attempt++) {
        if (mediakit_hdr_frame_budget_try_acquire(budget)) {
            assert(mediakit_hdr_frame_budget_in_flight(budget) <= 3);
            sched_yield();
            mediakit_hdr_frame_budget_release(budget);
        }
    }
    return NULL;
}

/** Verifies that competing frame producers never exceed a three-frame cap. */
static void
test_concurrent_budget(void)
{
    MediaKitHdrFrameBudget *budget = mediakit_hdr_frame_budget_new(3);
    assert(budget != NULL);
    pthread_t workers[4];
    for (unsigned int index = 0; index < 4; index++) {
        assert(pthread_create(&workers[index], NULL,
                              exercise_concurrent_budget, budget) == 0);
    }
    for (unsigned int index = 0; index < 4; index++) {
        assert(pthread_join(workers[index], NULL) == 0);
    }
    assert(mediakit_hdr_frame_budget_in_flight(budget) == 0);
    mediakit_hdr_frame_budget_unref(budget);
}

/** Runs only independent native resource-ownership contracts. */
int
main(void)
{
    test_texture_budget();
    test_invalid_and_single_slot_budget();
    test_concurrent_budget();
    return 0;
}
