// ocentry.c - adds or removes one kext entry in OpenCore's config.plist
// (Kernel > Add). See ocentry.h for who uses it.
//
// The file is edited as text so that the only change is the entry itself (the
// rest of the file keeps its exact bytes and formatting). The result is then
// parsed with CoreFoundation and compared with what it must be (the original
// property list plus, or minus, the entry). If the text edit does not give
// exactly that, the property list is written by CoreFoundation instead, which
// keeps every value but reformats the file. A timestamped backup of the
// original is written next to it before anything changes, and the new file
// replaces the old one only after it has been fully written.
#include "ocentry.h"

#include <CoreFoundation/CoreFoundation.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

// The kext of the command that is running. Set once by oc_entry_command.
static const OcKext* K;

typedef struct {
  char* p;
  size_t n;
} Buf;

static int read_file(const char* path, Buf* b) {
  FILE* f = fopen(path, "rb");
  if (!f) {
    perror(path);
    return -1;
  }
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (n <= 0 || n > 16 * 1024 * 1024) {
    fclose(f);
    fprintf(stderr, "%s: unexpected size\n", path);
    return -1;
  }
  b->p = malloc((size_t)n + 1);
  if (!b->p) {
    fclose(f);
    fprintf(stderr, "%s: out of memory\n", path);
    return -1;
  }
  b->n = fread(b->p, 1, (size_t)n, f);
  b->p[b->n] = 0;
  fclose(f);
  return b->n == (size_t)n ? 0 : -1;
}

static int write_file(const char* path, const void* p, size_t n) {
  char tmp[1100];
  int tn = snprintf(tmp, sizeof(tmp), "%s.%s-tmp", path, K->tag);
  if (tn < 0 || (size_t)tn >= sizeof(tmp)) {
    fprintf(stderr, "%s: path too long\n", path);
    return -1;
  }
  // Made new: whatever is at that name (a leftover, or a link someone planted)
  // is removed first, and O_EXCL never follows a link, so root writes only its
  // own file.
  unlink(tmp);
  int fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0644);
  FILE* f = fd < 0 ? NULL : fdopen(fd, "wb");
  if (!f) {
    perror(tmp);
    if (fd >= 0) {
      close(fd);
      unlink(tmp);
    }
    return -1;
  }
  size_t w = fwrite(p, 1, n, f);
  int rc = fflush(f) | fsync(fileno(f));
  fclose(f);
  if (w != n || rc != 0) {
    fprintf(stderr, "%s: write failed\n", tmp);
    unlink(tmp);
    return -1;
  }
  if (rename(tmp, path) != 0) {
    perror("rename");
    unlink(tmp);
    return -1;
  }
  return 0;
}

static CFPropertyListRef parse(const void* p, size_t n,
                               CFPropertyListFormat* fmt) {
  CFDataRef d = CFDataCreate(NULL, p, (CFIndex)n);
  CFPropertyListRef pl = CFPropertyListCreateWithData(
      NULL, d, kCFPropertyListMutableContainersAndLeaves, fmt, NULL);
  CFRelease(d);
  return pl;
}

static bool str_eq(CFTypeRef v, const char* s) {
  if (!v || CFGetTypeID(v) != CFStringGetTypeID()) return false;
  char buf[256];
  return CFStringGetCString(v, buf, sizeof(buf), kCFStringEncodingUTF8) &&
         !strcmp(buf, s);
}

static void set_str(CFMutableDictionaryRef d, CFStringRef key, const char* v) {
  CFStringRef s = CFStringCreateWithCString(NULL, v, kCFStringEncodingUTF8);
  CFDictionarySetValue(d, key, s);
  CFRelease(s);
}

// The entry: its keys in the order OpenCore's own sample uses, and their
// values. "Enabled" is the only one that is not a string.
static const char* kKeys[] = {"Arch",      "BundlePath",     "Comment",
                              "Enabled",   "ExecutablePath", "MaxKernel",
                              "MinKernel", "PlistPath"};
#define KEY_COUNT (sizeof(kKeys) / sizeof(kKeys[0]))
static const char* key_value(size_t i) {
  switch (i) {
    case 0:
      return "x86_64";
    case 1:
      return K->bundle;
    case 2:
      return K->comment;
    case 3:
      return NULL;  // <true/>
    case 4:
      return K->executable;
    case 5:
      return "";
    case 6:
      return K->minKernel;
    default:
      return "Contents/Info.plist";
  }
}

static CFMutableDictionaryRef make_entry(void) {
  CFMutableDictionaryRef d =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  for (size_t i = 0; i < KEY_COUNT; i++) {
    CFStringRef key =
        CFStringCreateWithCString(NULL, kKeys[i], kCFStringEncodingUTF8);
    const char* v = key_value(i);
    if (v)
      set_str(d, key, v);
    else
      CFDictionarySetValue(d, key, kCFBooleanTrue);
    CFRelease(key);
  }
  return d;
}

// Same entry as ours, ignoring the free-text Comment.
static bool same_entry(CFTypeRef e) {
  if (!e || CFGetTypeID(e) != CFDictionaryGetTypeID()) return false;
  CFMutableDictionaryRef a = CFDictionaryCreateMutableCopy(NULL, 0, e),
                         b = make_entry();
  CFDictionaryRemoveValue(a, CFSTR("Comment"));
  CFDictionaryRemoveValue(b, CFSTR("Comment"));
  bool same = CFEqual(a, b);
  CFRelease(a);
  CFRelease(b);
  return same;
}
// The entry earlier versions wrote: ours in every setting except MinKernel.
static bool old_entry(CFTypeRef e) {
  if (!K->oldMinKernel || !e || CFGetTypeID(e) != CFDictionaryGetTypeID() ||
      !str_eq(CFDictionaryGetValue(e, CFSTR("MinKernel")), K->oldMinKernel))
    return false;
  CFMutableDictionaryRef a = CFDictionaryCreateMutableCopy(NULL, 0, e);
  set_str(a, CFSTR("MinKernel"), K->minKernel);
  bool same = same_entry(a);
  CFRelease(a);
  return same;
}

// Writes into out the names of the settings in which e differs from our entry
// (Comment aside), for a message: "Enabled, MinKernel".
static void differing_keys(CFDictionaryRef e, char* out, size_t cap) {
  out[0] = 0;
  CFMutableDictionaryRef ours = make_entry();
  for (size_t i = 0; i < KEY_COUNT; i++) {
    if (!strcmp(kKeys[i], "Comment")) continue;
    CFStringRef key =
        CFStringCreateWithCString(NULL, kKeys[i], kCFStringEncodingUTF8);
    CFTypeRef a = CFDictionaryGetValue(e, key),
              b = CFDictionaryGetValue(ours, key);
    if (!a || !CFEqual(a, b)) {
      if (out[0]) strlcat(out, ", ", cap);
      strlcat(out, kKeys[i], cap);
    }
    CFRelease(key);
  }
  // a key our entry does not have
  const void* keys[64];
  CFIndex n = CFDictionaryGetCount(e);
  if (n <= 64) {
    CFDictionaryGetKeysAndValues(e, keys, NULL);
    for (CFIndex i = 0; i < n; i++)
      if (!CFDictionaryContainsKey(ours, keys[i])) {
        if (out[0]) strlcat(out, ", ", cap);
        strlcat(out, "an extra setting", cap);
        break;
      }
  }
  CFRelease(ours);
}

typedef struct {
  CFMutableDictionaryRef root;
  CFMutableArrayRef add;
  CFIndex lilu, ours, count;
  bool liluEnabled;
} Config;

static int load_config(CFPropertyListRef pl, CFPropertyListFormat fmt,
                       Config* c) {
  memset(c, 0, sizeof(*c));
  c->lilu = c->ours = -1;
  if (!pl || CFGetTypeID(pl) != CFDictionaryGetTypeID()) {
    fprintf(stderr, "not a property list dictionary\n");
    return -1;
  }
  if (fmt != kCFPropertyListXMLFormat_v1_0) {
    fprintf(stderr, "config.plist is not XML; OpenCore needs XML\n");
    return -1;
  }
  c->root = (CFMutableDictionaryRef)pl;
  CFTypeRef kernel = CFDictionaryGetValue(c->root, CFSTR("Kernel"));
  if (!kernel || CFGetTypeID(kernel) != CFDictionaryGetTypeID()) {
    fprintf(stderr,
            "no Kernel dictionary: is this an OpenCore config.plist?\n");
    return -1;
  }
  CFTypeRef add = CFDictionaryGetValue(kernel, CFSTR("Add"));
  if (!add || CFGetTypeID(add) != CFArrayGetTypeID()) {
    fprintf(stderr, "no Kernel > Add array\n");
    return -1;
  }
  c->add = (CFMutableArrayRef)add;
  c->count = CFArrayGetCount(c->add);
  for (CFIndex i = 0; i < c->count; i++) {
    CFTypeRef e = CFArrayGetValueAtIndex(c->add, i);
    if (CFGetTypeID(e) != CFDictionaryGetTypeID()) {
      fprintf(stderr, "Kernel > Add item %ld is not a dictionary; refusing\n",
              (long)i);
      return -1;
    }
    CFTypeRef bp = CFDictionaryGetValue(e, CFSTR("BundlePath"));
    if (str_eq(bp, "Lilu.kext") && c->lilu < 0) {
      c->lilu = i;
      c->liluEnabled =
          CFDictionaryGetValue(e, CFSTR("Enabled")) == kCFBooleanTrue;
    }
    if (str_eq(bp, K->bundle)) {
      if (c->ours >= 0) {
        fprintf(stderr, "%s is listed twice; fix it by hand\n", K->bundle);
        return -1;
      }
      c->ours = i;
    }
  }
  return 0;
}

static const char* find_from(const char* hay, const char* end,
                             const char* needle) {
  size_t n = strlen(needle);
  for (const char* p = hay; p && p + n <= end; p++)
    if (*p == *needle && !memcmp(p, needle, n)) return p;
  return NULL;
}

static const char* line_start(const char* base, const char* p) {
  while (p > base && p[-1] != '\n') p--;
  return p;
}

static bool only_space(const char* a, const char* b) {
  for (; a < b; a++)
    if (*a != ' ' && *a != '\t') return false;
  return true;
}

// Appends s to out as XML text ('&', '<' and '>' escaped). Returns the new
// length, which stays below cap.
static size_t xml_text(char* out, size_t len, size_t cap, const char* s) {
  for (; *s && len + 6 < cap; s++) {
    const char* rep = *s == '&' ? "&amp;" : *s == '<' ? "&lt;" : NULL;
    if (*s == '>') rep = "&gt;";
    if (rep)
      len += (size_t)snprintf(out + len, cap - len, "%s", rep);
    else
      out[len++] = *s;
  }
  out[len] = 0;
  return len;
}

// "<string>NAME.kext</string>", the line by which the text edits find our
// entry.
static void bundle_line(char* out, size_t cap) {
  size_t len = (size_t)snprintf(out, cap, "<string>");
  len = xml_text(out, len, cap - 16, K->bundle);
  snprintf(out + len, cap - len, "</string>");
}

// Text insertion of our entry before the closing </array> of Kernel > Add.
// Returns a malloc'ed buffer or NULL.
static char* text_add(const Buf* in, size_t* outLen) {
  const char *base = in->p, *end = in->p + in->n;
  const char* k = find_from(base, end, "<key>Kernel</key>");
  const char* a = k ? find_from(k, end, "<key>Add</key>") : NULL;
  if (!a) return NULL;
  // the value of the Add key must be an <array> (only whitespace in between)
  const char* open = a + strlen("<key>Add</key>");
  while (open < end &&
         (*open == ' ' || *open == '\t' || *open == '\n' || *open == '\r'))
    open++;
  if (end - open < 7 || strncmp(open, "<array>", 7) != 0) return NULL;
  int depth = 1;
  const char *p = open + strlen("<array>"), *close = NULL;
  while (p < end && depth > 0) {
    const char* lt = memchr(p, '<', (size_t)(end - p));
    if (!lt) return NULL;
    if (!strncmp(lt, "<array>", 7))
      depth++;
    else if (!strncmp(lt, "</array>", 8)) {
      if (--depth == 0) {
        close = lt;
        break;
      }
    }
    p = lt + 1;
  }
  if (!close) return NULL;
  const char* ls = line_start(base, close);
  if (!only_space(ls, close)) return NULL;
  size_t closeIndentLen = (size_t)(close - ls);
  char entryIndent[64], unit[16] = "\t";
  const char* firstDict = find_from(open, close, "<dict>");
  if (firstDict) {
    const char* ds = line_start(base, firstDict);
    size_t n = (size_t)(firstDict - ds);
    if (!only_space(ds, firstDict) || n >= sizeof(entryIndent)) return NULL;
    memcpy(entryIndent, ds, n);
    entryIndent[n] = 0;
    if (n > closeIndentLen && !memcmp(entryIndent, ls, closeIndentLen) &&
        n - closeIndentLen < sizeof(unit)) {
      memcpy(unit, entryIndent + closeIndentLen, n - closeIndentLen);
      unit[n - closeIndentLen] = 0;
    }
  } else {
    if (closeIndentLen + 1 >= sizeof(entryIndent)) return NULL;
    memcpy(entryIndent, ls, closeIndentLen);
    entryIndent[closeIndentLen] = 0;
    strlcat(entryIndent, ls[0] == ' ' ? "    " : "\t", sizeof(entryIndent));
    if (ls[0] == ' ') strlcpy(unit, "    ", sizeof(unit));
  }
  char entry[4096];
  size_t cap = sizeof(entry) - 128;  // room for the closing lines
  size_t len = (size_t)snprintf(entry, cap, "%s<dict>\n", entryIndent);
  for (size_t i = 0; i < KEY_COUNT && len < cap; i++) {
    len += (size_t)snprintf(entry + len, cap - len, "%s%s<key>%s</key>\n%s%s",
                            entryIndent, unit, kKeys[i], entryIndent, unit);
    if (len >= cap) return NULL;
    const char* v = key_value(i);
    if (v) {
      len += (size_t)snprintf(entry + len, cap - len, "<string>");
      if (len >= cap) return NULL;
      len = xml_text(entry, len, cap, v);
      len += (size_t)snprintf(entry + len, cap - len, "</string>\n");
    } else {
      len += (size_t)snprintf(entry + len, cap - len, "<true/>\n");
    }
  }
  if (len >= cap) return NULL;
  len += (size_t)snprintf(entry + len, sizeof(entry) - len, "%s</dict>\n",
                          entryIndent);
  size_t pre = (size_t)(ls - base);
  char* out = malloc(in->n + len + 1);
  if (!out) return NULL;
  memcpy(out, base, pre);
  memcpy(out + pre, entry, len);
  memcpy(out + pre + len, base + pre, in->n - pre);
  *outLen = in->n + len;
  out[*outLen] = 0;
  return out;
}

// Finds the <dict> ... </dict> that holds our BundlePath, when the file has
// exactly one. Sets *d to its "<dict>" and *e to its "</dict>".
static bool find_entry(const char* base, const char* end, const char** d,
                       const char** e) {
  char needle[600];
  bundle_line(needle, sizeof(needle));
  const char* m = find_from(base, end, needle);
  if (!m || find_from(m + 1, end, needle)) return false;
  *d = NULL;
  for (const char* p = m; p >= base + 6; p--)
    if (!strncmp(p, "<dict>", 6)) {
      *d = p;
      break;
    }
  *e = *d ? find_from(m, end, "</dict>") : NULL;
  if (!*d || !*e) return false;
  // nothing nested between the two
  return !find_from(*d + 6, *e, "<dict>") && !find_from(*d, m, "</dict>");
}

// Text removal of the lines of our entry. Returns a malloc'ed buffer or NULL.
static char* text_remove(const Buf* in, size_t* outLen) {
  const char *base = in->p, *end = in->p + in->n, *d, *e;
  if (!find_entry(base, end, &d, &e)) return NULL;
  const char* from = line_start(base, d);
  if (!only_space(from, d)) return NULL;
  const char* to = e + strlen("</dict>");
  if (to < end && *to == '\n')
    to++;
  else if (to + 1 < end && to[0] == '\r' && to[1] == '\n')  // CRLF file
    to += 2;
  else
    return NULL;
  size_t pre = (size_t)(from - base), post = (size_t)(end - to);
  char* out = malloc(pre + post + 1);
  if (!out) return NULL;
  memcpy(out, base, pre);
  memcpy(out + pre, to, post);
  *outLen = pre + post;
  out[*outLen] = 0;
  return out;
}

// Text change of the old MinKernel to the current one inside our entry.
// Returns a malloc'ed buffer or NULL.
static char* text_minkernel(const Buf* in, size_t* outLen) {
  const char *base = in->p, *end = in->p + in->n, *d, *e;
  if (!find_entry(base, end, &d, &e)) return NULL;
  const char* k = find_from(d, e, "<key>MinKernel</key>");
  if (!k || find_from(k + 1, e, "<key>MinKernel</key>")) return NULL;
  const char* v = k + strlen("<key>MinKernel</key>");
  while (v < e && (*v == ' ' || *v == '\t' || *v == '\n' || *v == '\r')) v++;
  char oldv[128], newv[128];
  snprintf(oldv, sizeof(oldv), "<string>%s</string>", K->oldMinKernel);
  snprintf(newv, sizeof(newv), "<string>%s</string>", K->minKernel);
  size_t on = strlen(oldv), nn = strlen(newv);
  if ((size_t)(e - v) < on || memcmp(v, oldv, on) != 0) return NULL;
  size_t pre = (size_t)(v - base), post = (size_t)(end - (v + on));
  char* out = malloc(pre + nn + post + 1);
  if (!out) return NULL;
  memcpy(out, base, pre);
  memcpy(out + pre, newv, nn);
  memcpy(out + pre + nn, v + on, post);
  *outLen = pre + nn + post;
  out[*outLen] = 0;
  return out;
}

static int backup(const char* path, const Buf* orig, char* out, size_t outLen) {
  char ts[32];
  time_t t = time(NULL);
  strftime(ts, sizeof(ts), "%Y%m%d-%H%M%S", localtime(&t));
  // room for the longest name below: ".backup-" ts "-99" "-pre-" tag
  if (strlen(path) + strlen(".backup--99-pre-") + strlen(ts) + strlen(K->tag) >=
      outLen) {
    fprintf(stderr, "%s: path too long\n", path);
    return -1;
  }
  snprintf(out, outLen, "%s.backup-%s-pre-%s", path, ts, K->tag);
  for (int i = 2; access(out, F_OK) == 0 && i < 100; i++)
    snprintf(out, outLen, "%s.backup-%s-%d-pre-%s", path, ts, i, K->tag);
  FILE* f = fopen(out, "wbx");
  if (!f) {
    perror(out);
    return -1;
  }
  size_t w = fwrite(orig->p, 1, orig->n, f);
  int rc = fflush(f) | fsync(fileno(f));
  fclose(f);
  if (w == orig->n && rc == 0) return 0;
  // a partial backup under the normal name could later be taken for a good one
  unlink(out);
  return -1;
}

int oc_entry_command(const char* what, const char* path, const OcKext* kext) {
  K = kext;
  Buf orig = {0};
  if (read_file(path, &orig) != 0) return 1;
  CFPropertyListFormat fmt = 0;
  CFPropertyListRef pl = parse(orig.p, orig.n, &fmt);
  Config c;
  if (load_config(pl, fmt, &c) != 0) return 1;

  if (!strcmp(what, "check")) {
    printf("%s: Kernel > Add has %ld entries; Lilu.kext %s; %s %s\n", path,
           (long)c.count,
           c.lilu < 0      ? "missing"
           : c.liluEnabled ? "enabled"
                           : "disabled",
           K->bundle, c.ours < 0 ? "not listed" : "listed");
    if (c.ours >= 0) {
      CFTypeRef e = CFArrayGetValueAtIndex(c.add, c.ours);
      bool en = CFDictionaryGetValue(e, CFSTR("Enabled")) == kCFBooleanTrue;
      char how[400];
      if (same_entry(e)) {
        snprintf(how, sizeof(how), "settings as expected");
      } else if (old_entry(e) && c.lilu >= 0 &&
                 c.ours > c.lilu) {  // what add updates
        snprintf(how, sizeof(how),
                 "old entry with MinKernel %s (current: %s): add updates it",
                 K->oldMinKernel, K->minKernel);
      } else {
        char keys[300];
        differing_keys(e, keys, sizeof(keys));
        snprintf(how, sizeof(how),
                 "settings differ from the expected entry (%s)", keys);
      }
      printf("  entry %ld, %s, %s, %s\n", (long)c.ours,
             en ? "enabled" : "DISABLED",
             c.lilu < 0        ? "Lilu is not listed"
             : c.ours > c.lilu ? "after Lilu"
                               : "BEFORE Lilu (must come after it)",
             how);
    }
    return 0;
  }

  CFMutableDictionaryRef expected =
      (CFMutableDictionaryRef)CFPropertyListCreateDeepCopy(
          NULL, pl, kCFPropertyListMutableContainersAndLeaves);
  Config ce;
  load_config(expected, fmt, &ce);
  char* text = NULL;
  size_t textLen = 0;
  char done[160];
  const char* verified = !strcmp(what, "add")
                             ? "equals the original plus the entry"
                             : "equals the original minus the entry";
  snprintf(done, sizeof(done), "%s",
           !strcmp(what, "add") ? "added" : "removed");
  if (!strcmp(what, "add")) {
    if (c.lilu < 0 || !c.liluEnabled) {
      fprintf(stderr, "Lilu.kext is not enabled in Kernel > Add; %s needs it\n",
              K->bundle);
      return 1;
    }
    if (c.ours >= 0) {
      CFTypeRef cur = CFArrayGetValueAtIndex(c.add, c.ours);
      bool same = same_entry(cur);
      if (same && c.ours > c.lilu) {
        printf("%s is already in Kernel > Add (entry %ld); nothing to change\n",
               K->bundle, (long)c.ours);
        return 0;
      }
      if (old_entry(cur) && c.ours > c.lilu) {
        // entry from an earlier version: only MinKernel changes
        CFMutableDictionaryRef e =
            (CFMutableDictionaryRef)CFArrayGetValueAtIndex(ce.add, c.ours);
        set_str(e, CFSTR("MinKernel"), K->minKernel);
        text = text_minkernel(&orig, &textLen);
        snprintf(done, sizeof(done), "updated MinKernel %s -> %s of",
                 K->oldMinKernel, K->minKernel);
        verified = "equals the original except for that MinKernel";
      } else {
        fprintf(stderr,
                "%s is listed but differs from the expected entry (or comes "
                "before Lilu); %s\n",
                K->bundle, K->removeHint);
        return 3;
      }
    } else {
      CFMutableDictionaryRef e = make_entry();
      CFArrayAppendValue(ce.add, e);
      CFRelease(e);
      text = text_add(&orig, &textLen);
    }
  } else if (!strcmp(what, "remove")) {
    if (c.ours < 0) {
      printf("%s is not in Kernel > Add; nothing to change\n", K->bundle);
      return 0;
    }
    CFArrayRemoveValueAtIndex(ce.add, c.ours);
    text = text_remove(&orig, &textLen);
  } else
    return 2;

  const void* outP = NULL;
  size_t outN = 0;
  CFDataRef cfOut = NULL;
  if (text) {
    CFPropertyListFormat f2;
    CFPropertyListRef got = parse(text, textLen, &f2);
    if (got && f2 == kCFPropertyListXMLFormat_v1_0 && CFEqual(got, expected)) {
      outP = text;
      outN = textLen;
    }
    if (got) CFRelease(got);
  }
  const char* how = "text edit, only the entry changes";
  if (!outP) {
    cfOut = CFPropertyListCreateData(NULL, expected,
                                     kCFPropertyListXMLFormat_v1_0, 0, NULL);
    if (!cfOut) {
      fprintf(stderr, "could not serialize the new property list\n");
      return 1;
    }
    outP = CFDataGetBytePtr(cfOut);
    outN = (size_t)CFDataGetLength(cfOut);
    how = "rewritten by CoreFoundation (same values, new formatting)";
  }
  char bak[1200];
  if (backup(path, &orig, bak, sizeof(bak)) != 0) {
    fprintf(stderr, "backup failed; nothing changed\n");
    return 1;
  }
  if (write_file(path, outP, outN) != 0) {
    fprintf(stderr, "write failed; the original is unchanged (backup %s)\n",
            bak);
    return 1;
  }

  // verify what is on disk now
  Buf now = {0};
  CFPropertyListFormat f3;
  CFPropertyListRef check =
      read_file(path, &now) == 0 ? parse(now.p, now.n, &f3) : NULL;
  bool ok = check && CFEqual(check, expected);
  printf("%s: %s %s (%s)\n  backup: %s\n", path, done, K->bundle, how, bak);
  if (!ok) {
    fprintf(stderr,
            "VERIFY FAILED: restore the backup above before rebooting\n");
    return 1;
  }
  printf("  verified: the file parses and %s\n", verified);
  return 0;
}
