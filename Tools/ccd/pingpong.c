// Cache-line ping-pong between two threads. Each thread can carry a Mach affinity tag
// (THREAD_AFFINITY_POLICY): on x86 xnu maps different tags to different affinity sets,
// one per last-level cache. Same tag -> same L3 (same CCD), different tags -> different L3.
// Usage: pingpong <tagA> <tagB> <rounds>   (tag 0 = no tag)
#include <mach/mach.h>
#include <mach/thread_policy.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

static _Alignas(128) _Atomic long flag;
static long rounds;
static int tags[2];
static _Atomic int ready;

static void set_tag(int tag) {
    if (!tag) return;
    thread_affinity_policy_data_t p = { tag };
    kern_return_t kr = thread_policy_set(mach_thread_self(), THREAD_AFFINITY_POLICY,
                                         (thread_policy_t)&p, THREAD_AFFINITY_POLICY_COUNT);
    if (kr != KERN_SUCCESS) fprintf(stderr, "thread_policy_set: %d\n", kr);
}

static void *pong(void *arg) {
    (void)arg;
    set_tag(tags[1]);
    atomic_fetch_add(&ready, 1);
    for (long i = 0; i < rounds; i++) {
        while (atomic_load_explicit(&flag, memory_order_acquire) != 2 * i + 1) ;
        atomic_store_explicit(&flag, 2 * i + 2, memory_order_release);
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: %s tagA tagB rounds\n", argv[0]); return 2; }
    tags[0] = atoi(argv[1]); tags[1] = atoi(argv[2]); rounds = atol(argv[3]);
    pthread_t t;
    pthread_create(&t, NULL, pong, NULL);
    set_tag(tags[0]);
    while (atomic_load(&ready) < 1) ;
    // warm-up so both threads are running on their final CPUs
    for (volatile int w = 0; w < 50000000; w++) ;
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    uint64_t t0 = mach_absolute_time();
    for (long i = 0; i < rounds; i++) {
        atomic_store_explicit(&flag, 2 * i + 1, memory_order_release);
        while (atomic_load_explicit(&flag, memory_order_acquire) != 2 * i + 2) ;
    }
    uint64_t t1 = mach_absolute_time();
    pthread_join(t, NULL);
    double ns = (double)(t1 - t0) * tb.numer / tb.denom / rounds;
    printf("tags %d/%d: %.1f ns per round trip\n", tags[0], tags[1], ns);
    return 0;
}
