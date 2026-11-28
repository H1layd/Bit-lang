/* HTTP bridge: use libcurl as a library, never the curl program.
 * Compiled to checked-in assembly; bit programs do not need a C compiler. */
#include <curl/curl.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#ifdef BIT_HTTP_LINUX
extern void bit_die(const char *, long) __asm__("_bit_die") __attribute__((noreturn));
char *bit_fetch(const char *, long) __asm__("_bit_fetch");
char *bit_http_post(const char *, const char *, long) __asm__("_bit_http_post");
void bit_download(const char *, const char *, long) __asm__("_bit_download");
#else
extern void bit_die(const char *, long) __attribute__((noreturn));
#endif

static pthread_once_t http_once = PTHREAD_ONCE_INIT;
static CURL *(*easy_init_fn)(void);
static CURLcode (*easy_setopt_fn)(CURL *, CURLoption, ...);
static CURLcode (*easy_perform_fn)(CURL *);
static void (*easy_cleanup_fn)(CURL *);
static int http_available;

static void http_initialize(void) {
#ifdef BIT_HTTP_LINUX
    void *library = dlopen("libcurl.so.4", RTLD_NOW | RTLD_LOCAL);
#else
    void *library = dlopen("/usr/lib/libcurl.4.dylib", RTLD_NOW | RTLD_LOCAL);
#endif
    if (!library) return;
    CURLcode (*global_init_fn)(long) = dlsym(library, "curl_global_init");
    easy_init_fn = dlsym(library, "curl_easy_init");
    easy_setopt_fn = dlsym(library, "curl_easy_setopt");
    easy_perform_fn = dlsym(library, "curl_easy_perform");
    easy_cleanup_fn = dlsym(library, "curl_easy_cleanup");
    if (!global_init_fn || !easy_init_fn || !easy_setopt_fn || !easy_perform_fn || !easy_cleanup_fn) return;
    if (global_init_fn(CURL_GLOBAL_DEFAULT) == CURLE_OK) http_available = 1;
}

typedef struct {
    char *body;
    size_t length, capacity, header_bytes;
    FILE *file;
    int error, length_seen, transfer_seen, location_seen;
} HttpOutput;

static int url_allowed(const char *url) {
    const char *authority;
    if (!strncasecmp(url, "https://", 8)) authority = url + 8;
    else if (!strncasecmp(url, "http://", 7)) authority = url + 7;
    else return 0;
    if (!*authority || *authority == '/' || *authority == '?' || *authority == '#') return 0;
    int in_authority = 1;
    for (const unsigned char *p = (const unsigned char *)authority; *p; ++p) {
        if (*p <= 32 || *p == 127 || *p == '\\') return 0;
        if (in_authority && *p == '@') return 0;
        if (*p == '/' || *p == '?' || *p == '#') in_authority = 0;
        if (*p == '%') {
            if (!p[1] || !p[2]) return 0;
            for (int i = 1; i <= 2; ++i) {
                unsigned char c = p[i] | 32;
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return 0;
            }
            p += 2;
        }
    }
    return 1;
}

static size_t http_body(char *data, size_t size, size_t count, void *opaque) {
    HttpOutput *out = opaque;
    if (count && size > SIZE_MAX / count) return 0;
    size_t n = size * count;
    if (out->file) return fwrite(data, 1, n, out->file);
    if (n > SIZE_MAX - out->length - 1) return 0;
    size_t needed = out->length + n + 1;
    if (needed > out->capacity) {
        size_t capacity = out->capacity ? out->capacity : 4096;
        while (capacity < needed) {
            if (capacity > SIZE_MAX / 2) { capacity = needed; break; }
            capacity *= 2;
        }
        char *next = realloc(out->body, capacity);
        if (!next) return 0;
        out->body = next;
        out->capacity = capacity;
    }
    memcpy(out->body + out->length, data, n);
    out->length += n;
    out->body[out->length] = 0;
    return n;
}

static int header_name(const char *s, size_t n, const char *name) {
    size_t length = strlen(name);
    return n > length && s[length] == ':' && !strncasecmp(s, name, length);
}

static size_t http_header(char *line, size_t size, size_t count, void *opaque) {
    HttpOutput *out = opaque;
    if (count && size > SIZE_MAX / count) return 0;
    size_t n = size * count;
    if (n > 8192 || n > 65536 - out->header_bytes) return 0;
    out->header_bytes += n;
    if (n >= 5 && !memcmp(line, "HTTP/", 5)) {
        out->header_bytes = n;
        out->length_seen = out->transfer_seen = out->location_seen = 0;
        return n;
    }
    if (header_name(line, n, "content-length")) {
        if (out->length_seen++ || out->transfer_seen) return 0;
    } else if (header_name(line, n, "transfer-encoding")) {
        if (out->transfer_seen++ || out->length_seen) return 0;
        const char *value = line + 18, *end = line + n;
        while (value < end && (*value == ' ' || *value == '\t')) ++value;
        while (end > value && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r' || end[-1] == '\n')) --end;
        if (end - value != 7 || strncasecmp(value, "chunked", 7)) return 0;
    } else if (header_name(line, n, "location")) {
        if (out->location_seen++) return 0;
        const char *value = line + 9, *end = line + n;
        while (value < end && (*value == ' ' || *value == '\t')) ++value;
        const char *authority = NULL;
        if (end - value >= 2 && value[0] == '/' && value[1] == '/') authority = value + 2;
        else if (end - value >= 7 && !strncasecmp(value, "http://", 7)) authority = value + 7;
        else if (end - value >= 8 && !strncasecmp(value, "https://", 8)) authority = value + 8;
        if (authority) {
            for (const char *p = authority; p < end && *p != '/' && *p != '?' && *p != '#' && *p != '\r' && *p != '\n'; ++p)
                if (*p == '@') return 0;
        }
    }
    return n;
}

static char *http_request(const char *url, const char *post, const char *path, long line) {
    CURL *easy = NULL;
    HttpOutput out = {0};
    char *temporary = NULL;
    int fd = -1, ok = 0, temporary_created = 0;
    if (!url_allowed(url)) goto done;
    pthread_once(&http_once, http_initialize);
    if (!http_available) {
#ifdef BIT_HTTP_LINUX
        bit_die("HTTP: не удалось загрузить системную библиотеку libcurl.so.4", line);
#else
        bit_die("HTTP: не удалось загрузить системную библиотеку libcurl", line);
#endif
    }
    if (!(easy = easy_init_fn())) goto done;
    if (path) {
        const char *slash = strrchr(path, '/');
        size_t prefix = slash ? (size_t)(slash - path + 1) : 0;
        const char suffix[] = ".bit-copy-XXXXXX";
        if (prefix > SIZE_MAX - sizeof(suffix)) goto done;
        temporary = malloc(prefix + sizeof(suffix));
        if (!temporary) goto done;
        memcpy(temporary, path, prefix);
        memcpy(temporary + prefix, suffix, sizeof(suffix));
        fd = mkstemp(temporary);
        if (fd < 0) goto done;
        temporary_created = 1;
        out.file = fdopen(fd, "wb");
        if (!out.file) goto done;
        fd = -1;
    }
#define SET(option, value) do { if (easy_setopt_fn(easy, option, value) != CURLE_OK) goto done; } while (0)
    SET(CURLOPT_URL, url);
    SET(CURLOPT_FOLLOWLOCATION, 1L);
    SET(CURLOPT_MAXREDIRS, 20L);
    SET(CURLOPT_PROTOCOLS, (long)(CURLPROTO_HTTP | CURLPROTO_HTTPS));
    SET(CURLOPT_REDIR_PROTOCOLS, (long)(CURLPROTO_HTTP | CURLPROTO_HTTPS));
    SET(CURLOPT_NOSIGNAL, 1L);
    SET(CURLOPT_SSL_VERIFYPEER, 1L);
    SET(CURLOPT_SSL_VERIFYHOST, 2L);
    SET(CURLOPT_WRITEFUNCTION, http_body);
    SET(CURLOPT_WRITEDATA, &out);
    SET(CURLOPT_HEADERFUNCTION, http_header);
    SET(CURLOPT_HEADERDATA, &out);
    if (post) SET(CURLOPT_POSTFIELDS, post);
    if (easy_perform_fn(easy) != CURLE_OK) goto done;
    if (out.file) {
        int close_error = fclose(out.file);
        out.file = NULL;
        if (close_error || rename(temporary, path)) goto done;
    } else if (!out.body) {
        out.body = calloc(1, 1);
        if (!out.body) goto done;
    }
    ok = 1;
done:
    if (easy) easy_cleanup_fn(easy);
    if (out.file) fclose(out.file);
    if (fd >= 0) close(fd);
    if (temporary) { if (!ok && temporary_created) unlink(temporary); free(temporary); }
    if (!ok) { free(out.body); bit_die("ошибка HTTP-запроса", line); }
    return out.body;
}

char *bit_fetch(const char *url, long line) { return http_request(url, NULL, NULL, line); }
char *bit_http_post(const char *url, const char *body, long line) { return http_request(url, body, NULL, line); }
void bit_download(const char *url, const char *path, long line) { (void)http_request(url, NULL, path, line); }
