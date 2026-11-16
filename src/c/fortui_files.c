/* Directory handles keep platform structures outside the Fortran ABI. */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
typedef struct { HANDLE handle; WIN32_FIND_DATAW data; int first; } listing;
static wchar_t *wide(const char *s) {
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
    wchar_t *w = n ? malloc((size_t)n * sizeof *w) : NULL;
    if (w) MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}
void *fortui_dir_open(const char *path) {
    size_t n = strlen(path);
    char *pattern = malloc(n + 3);
    if (!pattern) return NULL;
    memcpy(pattern, path, n); strcpy(pattern + n, "/*");
    wchar_t *w = wide(pattern); free(pattern);
    listing *d = calloc(1, sizeof *d);
    if (!d || !w) { free(d); free(w); return NULL; }
    d->handle = FindFirstFileW(w, &d->data); free(w);
    if (d->handle == INVALID_HANDLE_VALUE) { free(d); return NULL; }
    d->first = 1;
    return d;
}
int fortui_dir_next(void *handle, char *name, int capacity, int *directory) {
    listing *d = handle;
    if (!d->first && !FindNextFileW(d->handle, &d->data))
        return GetLastError() == ERROR_NO_MORE_FILES ? 0 : -1;
    d->first = 0;
    *directory = (d->data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY ? 1 : 0) |
        (d->data.dwFileAttributes & (FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM) ? 2 : 0);
    return WideCharToMultiByte(CP_UTF8, 0, d->data.cFileName, -1, name, capacity,
                               NULL, NULL) ? 1 : -1;
}
void fortui_dir_close(void *handle) {
    listing *d = handle; FindClose(d->handle); free(d);
}
int fortui_file_directory(const char *path) {
    wchar_t *w = wide(path);
    if (!w) return 0;
    DWORD a = GetFileAttributesW(w); free(w);
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY);
}
#else
#include <dirent.h>
#include <sys/stat.h>
#include <errno.h>
typedef struct { DIR *dir; char *path; } listing;
void *fortui_dir_open(const char *path) {
    listing *d = calloc(1, sizeof *d);
    if (!d) return NULL;
    d->dir = opendir(path); d->path = strdup(path);
    if (!d->dir || !d->path) {
        if (d->dir) closedir(d->dir);
        free(d->path); free(d); return NULL;
    }
    return d;
}
int fortui_dir_next(void *handle, char *name, int capacity, int *directory) {
    listing *d = handle;
    errno = 0;
    struct dirent *e = readdir(d->dir);
    if (!e) return errno ? -1 : 0;
    if (strlen(e->d_name) >= (size_t)capacity) return -1;
    strcpy(name, e->d_name);
    size_t n = strlen(d->path) + strlen(name) + 2;
    char *full = malloc(n);
    if (!full) return -1;
    snprintf(full, n, "%s/%s", d->path, name);
    struct stat s;
    *directory = stat(full, &s) == 0 && S_ISDIR(s.st_mode);
    free(full); return 1;
}
void fortui_dir_close(void *handle) {
    listing *d = handle; closedir(d->dir); free(d->path); free(d);
}
int fortui_file_directory(const char *path) {
    struct stat s; return stat(path, &s) == 0 && S_ISDIR(s.st_mode);
}
#endif

static FILE *file_open(const char *path) {
#ifdef _WIN32
    wchar_t *w = wide(path);
    if (!w) return NULL;
    FILE *f = _wfopen(w, L"rb"); free(w); return f;
#else
    return fopen(path, "rb");
#endif
}
int fortui_file_readable(const char *path) {
    if (fortui_file_directory(path)) return 0;
    FILE *f = file_open(path);
    if (!f) return 0;
    fclose(f); return 1;
}
void *fortui_file_open(const char *path, long long *size) {
    *size = -1;
    if (fortui_file_directory(path)) return NULL;
    FILE *f = file_open(path);
    if (!f) return NULL;
#ifdef _WIN32
    if (_fseeki64(f, 0, SEEK_END) == 0) *size = _ftelli64(f);
    _fseeki64(f, 0, SEEK_SET);
#else
    if (fseeko(f, 0, SEEK_END) == 0) *size = (long long)ftello(f);
    fseeko(f, 0, SEEK_SET);
#endif
    if (*size < 0) { fclose(f); return NULL; }
    return f;
}
int fortui_file_copy(void *handle, signed char *bytes, int size) {
    FILE *f = handle;
    return fread(bytes, 1, (size_t)size, f) == (size_t)size ? 0 : -1;
}
void fortui_file_close(void *handle) { fclose(handle); }

int fortui_file_absolute(const char *path, char *out, int capacity) {
#ifdef _WIN32
    wchar_t *w = wide(path);
    if (!w) return 0;
    DWORD n = GetFullPathNameW(w, 0, NULL, NULL);
    wchar_t *full = n ? malloc((size_t)n * sizeof *full) : NULL;
    int ok = full && GetFullPathNameW(w, n, full, NULL) != 0 &&
        WideCharToMultiByte(CP_UTF8, 0, full, -1, out, capacity, NULL, NULL) != 0;
    free(w); free(full); return ok;
#else
    char *full = realpath(path, NULL);
    if (!full) return 0;
    int ok = strlen(full) < (size_t)capacity;
    if (ok) strcpy(out, full);
    free(full); return ok;
#endif
}
