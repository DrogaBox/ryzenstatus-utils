// Minimal kernel-style sysctl macros for the user-space test build.
#pragma once
struct sysctl_oid { int dummy; };
struct sysctl_req { void *newptr; };
#define SYSCTL_HANDLER_ARGS (struct sysctl_oid *oidp, void *arg1, int arg2, struct sysctl_req *req)
#define CTLTYPE_INT 0
#define CTLTYPE_STRING 0
#define CTLFLAG_RW 0
#define CTLFLAG_RD 0
#define CTLFLAG_ANYBODY 0
#define CTLFLAG_LOCKED 0
#define OID_AUTO 0
#define SYSCTL_PROC(parent, nbr, name, kind, a1, a2, handler, fmt, descr) struct sysctl_oid sysctl_##parent##_##name
#define SYSCTL_INT(parent, nbr, name, access, ptr, val, descr) struct sysctl_oid sysctl_##parent##_##name
static int g_test_int_in = -1;
static const char *g_test_str_out;
static inline int sysctl_handle_int(struct sysctl_oid *, int *v, int, struct sysctl_req *req) {
    if (req && req->newptr) *v = g_test_int_in;
    return 0;
}
static inline int sysctl_handle_string(struct sysctl_oid *, char *s, int, struct sysctl_req *) {
    static char last[512];
    strncpy(last, s, sizeof(last) - 1);
    g_test_str_out = last;
    return 0;
}
static inline void sysctl_register_oid(struct sysctl_oid *) {}
