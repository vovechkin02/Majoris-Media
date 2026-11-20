#ifndef MEDIAKIT_HDR_FRAME_BUDGET_H
#define MEDIAKIT_HDR_FRAME_BUDGET_H

#include <stdbool.h>

/* Private, GTK-independent lifetime tracker for immutable HDR GL textures. */
#if defined(__GNUC__) || defined(__clang__)
#define MEDIAKIT_HDR_PRIVATE __attribute__((visibility("hidden")))
#else
#define MEDIAKIT_HDR_PRIVATE
#endif
typedef struct MediaKitHdrFrameBudget MediaKitHdrFrameBudget;

/** Allocates a bounded tracker, with one reference owned by its producer. */
MEDIAKIT_HDR_PRIVATE MediaKitHdrFrameBudget *mediakit_hdr_frame_budget_new(unsigned int maximum);

/** Adds a reference retained by a GdkTexture release callback. */
MEDIAKIT_HDR_PRIVATE MediaKitHdrFrameBudget *mediakit_hdr_frame_budget_ref(MediaKitHdrFrameBudget *budget);

/** Releases an owner reference; outstanding texture references remain valid. */
MEDIAKIT_HDR_PRIVATE void mediakit_hdr_frame_budget_unref(MediaKitHdrFrameBudget *budget);

/** Atomically reserves one texture slot, or declines without changing state. */
MEDIAKIT_HDR_PRIVATE bool mediakit_hdr_frame_budget_try_acquire(MediaKitHdrFrameBudget *budget);

/** Releases precisely one previously acquired slot. */
MEDIAKIT_HDR_PRIVATE void mediakit_hdr_frame_budget_release(MediaKitHdrFrameBudget *budget);

/** Returns an instantaneous diagnostic count, not an output-HDR capability. */
MEDIAKIT_HDR_PRIVATE unsigned int mediakit_hdr_frame_budget_in_flight(const MediaKitHdrFrameBudget *budget);

#endif
