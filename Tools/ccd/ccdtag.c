// DYLD_INSERT_LIBRARIES shim: gives every thread of the process the same Mach affinity tag,
// so xnu keeps them in one affinity set (one L3 = one CCD on the 5900XT).
// CCDTAG=<n> picks the tag (default 1). Load with:
//   DYLD_INSERT_LIBRARIES=/path/libccdtag.dylib CCDTAG=1 <program>
#include <mach/mach.h>
#include <mach/thread_policy.h>
#include <pthread.h>
#include <stdlib.h>

static int g_tag = 1;

static void tag_self(void) {
    thread_affinity_policy_data_t p = { g_tag };
    thread_policy_set(mach_thread_self(), THREAD_AFFINITY_POLICY,
                      (thread_policy_t)&p, THREAD_AFFINITY_POLICY_COUNT);
}

struct start { void *(*fn)(void *); void *arg; };

static void *trampoline(void *a) {
    struct start s = *(struct start *)a;
    free(a);
    tag_self();
    return s.fn(s.arg);
}

static int my_pthread_create(pthread_t *t, const pthread_attr_t *attr, void *(*fn)(void *), void *arg) {
    struct start *s = malloc(sizeof *s);
    if (!s) return pthread_create(t, attr, fn, arg);
    s->fn = fn; s->arg = arg;
    int r = pthread_create(t, attr, trampoline, s);
    if (r) free(s);
    return r;
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement, *original; } interposers[] = {
    { (const void *)my_pthread_create, (const void *)pthread_create },
};

__attribute__((constructor)) static void init(void) {
    const char *e = getenv("CCDTAG");
    if (e && atoi(e) > 0) g_tag = atoi(e);
    tag_self();
}
