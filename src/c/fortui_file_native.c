/* OS dialog ABI only. Requests and application state belong to Fortran. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !defined(_WIN32) && !defined(__APPLE__) && !defined(__EMSCRIPTEN__)
#include <dlfcn.h>
#include <time.h>
/* Public libdbus iterator ABI, dbus-message.h. No private fields are accessed.
 */
typedef struct {
  void *dummy1, *dummy2;
  uint32_t dummy3;
  int dummy4, dummy5, dummy6, dummy7, dummy8, dummy9, dummy10, dummy11, pad1;
  void *pad2, *pad3;
} bus_iter;
typedef void bus_conn;
typedef void bus_msg;
#define API(ret, name, args) static ret(*name) args
API(bus_conn *, dbus_bus_get_private, (int, void *));
API(const char *, dbus_bus_get_unique_name, (bus_conn *));
API(void, dbus_bus_add_match, (bus_conn *, const char *, void *));
API(void, dbus_connection_set_exit_on_disconnect, (bus_conn *, int));
API(int, dbus_connection_get_is_connected, (bus_conn *));
API(int, dbus_connection_read_write, (bus_conn *, int));
API(bus_msg *, dbus_connection_pop_message, (bus_conn *));
API(int, dbus_connection_send, (bus_conn *, bus_msg *, uint32_t *));
API(void, dbus_connection_flush, (bus_conn *));
API(void, dbus_connection_close, (bus_conn *));
API(void, dbus_connection_unref, (bus_conn *));
API(bus_msg *, dbus_message_new_method_call,
    (const char *, const char *, const char *, const char *));
API(void, dbus_message_unref, (bus_msg *));
API(int, dbus_message_get_type, (bus_msg *));
API(uint32_t, dbus_message_get_reply_serial, (bus_msg *));
API(const char *, dbus_message_get_path, (bus_msg *));
API(int, dbus_message_is_signal, (bus_msg *, const char *, const char *));
API(void, dbus_message_iter_init_append, (bus_msg *, bus_iter *));
API(int, dbus_message_iter_init, (bus_msg *, bus_iter *));
API(int, dbus_message_iter_next, (bus_iter *));
API(int, dbus_message_iter_get_arg_type, (bus_iter *));
API(void, dbus_message_iter_get_basic, (bus_iter *, void *));
API(void, dbus_message_iter_recurse, (bus_iter *, bus_iter *));
API(int, dbus_message_iter_append_basic, (bus_iter *, int, const void *));
API(int, dbus_message_iter_open_container,
    (bus_iter *, int, const char *, bus_iter *));
API(int, dbus_message_iter_close_container, (bus_iter *, bus_iter *));
#undef API
static void *bus_library;
static int load_bus(void) {
  if (bus_library)
    return 1;
  void *lib = dlopen("libdbus-1.so.3", RTLD_NOW | RTLD_LOCAL);
  if (!lib)
    return 0;
#define LOAD(name)                                                             \
  do {                                                                         \
    *(void **)(&name) = dlsym(lib, #name);                                     \
    if (!name)                                                                 \
      goto fail;                                                               \
  } while (0)
  LOAD(dbus_bus_get_private);
  LOAD(dbus_bus_get_unique_name);
  LOAD(dbus_bus_add_match);
  LOAD(dbus_connection_set_exit_on_disconnect);
  LOAD(dbus_connection_get_is_connected);
  LOAD(dbus_connection_read_write);
  LOAD(dbus_connection_pop_message);
  LOAD(dbus_connection_send);
  LOAD(dbus_connection_flush);
  LOAD(dbus_connection_close);
  LOAD(dbus_connection_unref);
  LOAD(dbus_message_new_method_call);
  LOAD(dbus_message_unref);
  LOAD(dbus_message_get_type);
  LOAD(dbus_message_get_reply_serial);
  LOAD(dbus_message_get_path);
  LOAD(dbus_message_is_signal);
  LOAD(dbus_message_iter_init_append);
  LOAD(dbus_message_iter_init);
  LOAD(dbus_message_iter_next);
  LOAD(dbus_message_iter_get_arg_type);
  LOAD(dbus_message_iter_get_basic);
  LOAD(dbus_message_iter_recurse);
  LOAD(dbus_message_iter_append_basic);
  LOAD(dbus_message_iter_open_container);
  LOAD(dbus_message_iter_close_container);
#undef LOAD
  bus_library = lib;
  return 1;
fail:
  dlclose(lib);
  return 0;
}
typedef struct {
  int state;
  char *path;
  bus_conn *conn;
  uint32_t serial;
  int awaiting_reply;
  time_t sent;
  char request[256];
} picker;
static const char *destination = "org.freedesktop.portal.Desktop";
static const char *request_interface = "org.freedesktop.portal.Request";
static int basic(bus_iter *i, int type, const void *value) {
  return dbus_message_iter_append_basic(i, type, value);
}
static int option(bus_iter *dict, const char *key, const char *signature,
                  const void *value) {
  bus_iter entry, variant;
  return dbus_message_iter_open_container(dict, 'e', NULL, &entry) &&
         basic(&entry, 's', &key) &&
         dbus_message_iter_open_container(&entry, 'v', signature, &variant) &&
         basic(&variant, signature[0], value) &&
         dbus_message_iter_close_container(&entry, &variant) &&
         dbus_message_iter_close_container(dict, &entry);
}
static int folder_option(bus_iter *dict, const char *folder) {
  bus_iter entry, variant, bytes;
  const char *key = "current_folder";
  if (!dbus_message_iter_open_container(dict, 'e', NULL, &entry) ||
      !basic(&entry, 's', &key) ||
      !dbus_message_iter_open_container(&entry, 'v', "ay", &variant) ||
      !dbus_message_iter_open_container(&variant, 'a', "y", &bytes))
    return 0;
  for (size_t n = 0; n <= strlen(folder); ++n)
    if (!basic(&bytes, 'y', folder + n))
      return 0;
  return dbus_message_iter_close_container(&variant, &bytes) &&
         dbus_message_iter_close_container(&entry, &variant) &&
         dbus_message_iter_close_container(dict, &entry);
}
static int filters_option(bus_iter *dict, const char *extensions) {
  bus_iter entry, variant, filters, filter, patterns, pattern;
  const char *key = "filters", *label = "Supported files";
  if (!*extensions)
    return 1;
  if (!dbus_message_iter_open_container(dict, 'e', NULL, &entry) ||
      !basic(&entry, 's', &key) ||
      !dbus_message_iter_open_container(&entry, 'v', "a(sa(us))", &variant) ||
      !dbus_message_iter_open_container(&variant, 'a', "(sa(us))", &filters) ||
      !dbus_message_iter_open_container(&filters, 'r', NULL, &filter) ||
      !basic(&filter, 's', &label) ||
      !dbus_message_iter_open_container(&filter, 'a', "(us)", &patterns))
    return 0;
  const char *at = extensions;
  while (*at) {
    const char *end = strchr(at, ',');
    size_t n = end ? (size_t)(end - at) : strlen(at);
    char glob[512];
    size_t k = 0;
    glob[k++] = '*';
    /* Portal globs are case-sensitive. Offer both cases for each letter. */
    for (size_t j = 0; j < n; ++j) {
      unsigned char c = (unsigned char)at[j];
      if (k + 5 >= sizeof glob)
        return 0;
      if (c >= 'a' && c <= 'z') {
        glob[k++] = '[';
        glob[k++] = c;
        glob[k++] = c - 32;
        glob[k++] = ']';
      } else if (c >= 'A' && c <= 'Z') {
        glob[k++] = '[';
        glob[k++] = c + 32;
        glob[k++] = c;
        glob[k++] = ']';
      } else
        glob[k++] = (char)c;
    }
    glob[k] = 0;
    const char *g = glob;
    uint32_t type = 0;
    if (!dbus_message_iter_open_container(&patterns, 'r', NULL, &pattern) ||
        !basic(&pattern, 'u', &type) || !basic(&pattern, 's', &g) ||
        !dbus_message_iter_close_container(&patterns, &pattern))
      return 0;
    if (!end)
      break;
    at = end + 1;
  }
  if (!dbus_message_iter_close_container(&filter, &patterns) ||
      !dbus_message_iter_close_container(&filters, &filter))
    return 0;
  label = "All files";
  const char *all = "*";
  uint32_t zero = 0;
  return dbus_message_iter_open_container(&filters, 'r', NULL, &filter) &&
         basic(&filter, 's', &label) &&
         dbus_message_iter_open_container(&filter, 'a', "(us)", &patterns) &&
         dbus_message_iter_open_container(&patterns, 'r', NULL, &pattern) &&
         basic(&pattern, 'u', &zero) && basic(&pattern, 's', &all) &&
         dbus_message_iter_close_container(&patterns, &pattern) &&
         dbus_message_iter_close_container(&filter, &patterns) &&
         dbus_message_iter_close_container(&filters, &filter) &&
         dbus_message_iter_close_container(&variant, &filters) &&
         dbus_message_iter_close_container(&entry, &variant) &&
         dbus_message_iter_close_container(dict, &entry);
}
static int hex_digit(unsigned char c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}
static char *uri_path(const char *uri) {
  const char *s;
  if (!strncmp(uri, "file:///", 8))
    s = uri + 7;
  else if (!strncmp(uri, "file://localhost/", 17))
    s = uri + 16;
  else
    return NULL;
  char *out = malloc(strlen(s) + 1);
  if (!out)
    return NULL;
  size_t n = 0;
  for (size_t j = 0; s[j]; ++j) {
    unsigned char c = (unsigned char)s[j];
    if (c == '%') {
      if (!s[j + 1] || !s[j + 2]) {
        free(out);
        return NULL;
      }
      int a = hex_digit(s[j + 1]), b = hex_digit(s[j + 2]);
      if (a < 0 || b < 0 || (a == 0 && b == 0)) {
        free(out);
        return NULL;
      }
      c = (unsigned char)(16 * a + b);
      j += 2;
    }
    out[n++] = (char)c;
  }
  out[n] = 0;
  return out;
}
void fortui_file_native_close(void *opaque);
void *fortui_file_native_open(void *parent, int64_t xid, const char *title,
                              const char *folder, const char *extensions) {
  (void)parent;
  if (!load_bus())
    return NULL;
  picker *p = calloc(1, sizeof *p);
  if (!p)
    return NULL;
  p->state = 1;
  p->conn = dbus_bus_get_private(0, NULL);
  if (!p->conn) {
    free(p);
    return NULL;
  }
  dbus_connection_set_exit_on_disconnect(p->conn, 0);
  /* Subscribe before OpenFile: a response can precede its method reply. */
  dbus_bus_add_match(
      p->conn,
      "type='signal',sender='org.freedesktop.portal.Desktop',interface='org."
      "freedesktop.portal.Request',member='Response'",
      NULL);
  static uint64_t serial;
  char token[64], sender[128], owner[64];
  snprintf(token, sizeof token, "fortui_%llu", (unsigned long long)++serial);
  snprintf(sender, sizeof sender, "%s", dbus_bus_get_unique_name(p->conn) + 1);
  for (char *s = sender; *s; ++s)
    if (*s == '.')
      *s = '_';
  snprintf(p->request, sizeof p->request,
           "/org/freedesktop/portal/desktop/request/%s/%s", sender, token);
  snprintf(owner, sizeof owner, "x11:%llx", (unsigned long long)xid);
  const char *parent_name = xid ? owner : "", *handle_token = token;
  bus_msg *m = dbus_message_new_method_call(
      destination, "/org/freedesktop/portal/desktop",
      "org.freedesktop.portal.FileChooser", "OpenFile");
  if (!m) {
    fortui_file_native_close(p);
    return NULL;
  }
  bus_iter args, options;
  int modal = 1;
  dbus_message_iter_init_append(m, &args);
  int ok = basic(&args, 's', &parent_name) && basic(&args, 's', &title) &&
           dbus_message_iter_open_container(&args, 'a', "{sv}", &options) &&
           option(&options, "handle_token", "s", &handle_token) &&
           option(&options, "modal", "b", &modal) &&
           folder_option(&options, folder) &&
           filters_option(&options, extensions) &&
           dbus_message_iter_close_container(&args, &options) &&
           dbus_connection_send(p->conn, m, &p->serial);
  dbus_message_unref(m);
  if (!ok) {
    fortui_file_native_close(p);
    return NULL;
  }
  dbus_connection_flush(p->conn);
  p->awaiting_reply = 1;
  p->sent = time(NULL);
  return p;
}
static void response(picker *p, bus_msg *m) {
  bus_iter args, dict, entry, variant, array;
  uint32_t code;
  if (!dbus_message_iter_init(m, &args) ||
      dbus_message_iter_get_arg_type(&args) != 'u') {
    p->state = 4;
    return;
  }
  dbus_message_iter_get_basic(&args, &code);
  if (code != 0) {
    p->state = code == 1 ? 3 : 4;
    return;
  }
  p->state = 4;
  if (!dbus_message_iter_next(&args) ||
      dbus_message_iter_get_arg_type(&args) != 'a')
    return;
  dbus_message_iter_recurse(&args, &dict);
  while (dbus_message_iter_get_arg_type(&dict) == 'e') {
    const char *key = NULL;
    dbus_message_iter_recurse(&dict, &entry);
    if (dbus_message_iter_get_arg_type(&entry) != 's')
      return;
    dbus_message_iter_get_basic(&entry, &key);
    if (!dbus_message_iter_next(&entry) ||
        dbus_message_iter_get_arg_type(&entry) != 'v')
      return;
    dbus_message_iter_recurse(&entry, &variant);
    if (!strcmp(key, "uris") &&
        dbus_message_iter_get_arg_type(&variant) == 'a') {
      dbus_message_iter_recurse(&variant, &array);
      if (dbus_message_iter_get_arg_type(&array) == 's') {
        const char *uri = NULL;
        dbus_message_iter_get_basic(&array, &uri);
        p->path = uri_path(uri);
        if (p->path)
          p->state = 2;
      }
      return;
    }
    dbus_message_iter_next(&dict);
  }
}
int fortui_file_native_poll(void *opaque) {
  picker *p = opaque;
  if (!p)
    return 5;
  if (p->state != 1)
    return p->state;
  if (!dbus_connection_read_write(p->conn, 0))
    return p->state = 4;
  bus_msg *m;
  while ((m = dbus_connection_pop_message(p->conn))) {
    const char *path = dbus_message_get_path(m);
    if (p->awaiting_reply && dbus_message_get_reply_serial(m) == p->serial) {
      p->awaiting_reply = 0;
      if (dbus_message_get_type(m) == 3)
        p->state = 5;
      else {
        bus_iter a;
        const char *handle = NULL;
        if (dbus_message_iter_init(m, &a) &&
            dbus_message_iter_get_arg_type(&a) == 'o') {
          dbus_message_iter_get_basic(&a, &handle);
          snprintf(p->request, sizeof p->request, "%s", handle);
        } else
          p->state = 4;
      }
    }
    if (p->state == 1 && path && !strcmp(path, p->request) &&
        dbus_message_is_signal(m, request_interface, "Response"))
      response(p, m);
    dbus_message_unref(m);
  }
  if (p->awaiting_reply && time(NULL) - p->sent >= 5)
    p->state = 5;
  return p->state;
}
void fortui_file_native_close(void *opaque) {
  picker *p = opaque;
  if (!p)
    return;
  if (p->conn) {
    if (p->state == 1 && p->request[0] &&
        dbus_connection_get_is_connected(p->conn)) {
      bus_msg *m = dbus_message_new_method_call(destination, p->request,
                                                request_interface, "Close");
      if (m) {
        dbus_connection_send(p->conn, m, NULL);
        dbus_message_unref(m);
        dbus_connection_flush(p->conn);
      }
    }
    dbus_connection_close(p->conn);
    dbus_connection_unref(p->conn);
  }
  free(p->path);
  free(p);
}
#elif defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <shobjidl.h>
#include <windows.h>
typedef struct {
  LONG state, cancelled;
  char *path, *title, *folder, *extensions;
  HWND parent;
  HANDLE thread;
  DWORD thread_id;
} picker;
static wchar_t *wide(const char *s) {
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
  wchar_t *w = n ? malloc((size_t)n * sizeof *w) : NULL;
  if (w)
    MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
  return w;
}
static DWORD WINAPI choose_file(void *opaque) {
  picker *p = opaque;
  int state = 5;
  HMODULE lib = LoadLibraryW(L"ole32.dll");
  if (!lib) {
    InterlockedExchange((LONG *)&p->state, state);
    return 0;
  }
  HRESULT(WINAPI * init)(LPVOID, DWORD) =
      (void *)GetProcAddress(lib, "CoInitializeEx");
  HRESULT(WINAPI * create)(REFCLSID, LPUNKNOWN, DWORD, REFIID, LPVOID *) =
      (void *)GetProcAddress(lib, "CoCreateInstance");
  void(WINAPI * uninit)(void) = (void *)GetProcAddress(lib, "CoUninitialize");
  void(WINAPI * release)(void *) = (void *)GetProcAddress(lib, "CoTaskMemFree");
  const CLSID class_id = {0xdc1c5a9c,
                          0xe88a,
                          0x4dde,
                          {0xa5, 0xa1, 0x60, 0xf8, 0x2a, 0x20, 0xae, 0xf7}};
  const IID interface_id = {0xd57c7288,
                            0xd4ad,
                            0x4768,
                            {0xbe, 0x02, 0x9d, 0x96, 0x95, 0x32, 0xd9, 0x60}};
  const IID shell_id = {0x43826d1e,
                        0xe718,
                        0x42ee,
                        {0xbc, 0x55, 0xa1, 0xe2, 0x61, 0xc3, 0x7b, 0xfe}};
  IFileOpenDialog *dialog = NULL;
  HRESULT hr = init && create && uninit && release
                   ? init(NULL, COINIT_APARTMENTTHREADED)
                   : E_FAIL;
  if (SUCCEEDED(hr)) {
    if (SUCCEEDED(create(&class_id, NULL, CLSCTX_INPROC_SERVER, &interface_id,
                         (void **)&dialog))) {
      wchar_t *title = wide(p->title), *folder = wide(p->folder);
      if (title)
        IFileOpenDialog_SetTitle(dialog, title);
      IFileOpenDialog_SetOptions(dialog,
                                 FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST |
                                     FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR);
      wchar_t *patterns = NULL;
      if (*p->extensions) {
        size_t n = strlen(p->extensions);
        char *filters = malloc(2 * n + 2);
        if (filters) {
          size_t k = 0;
          filters[k++] = '*';
          for (size_t j = 0; j < n; ++j) {
            if (p->extensions[j] == ',') {
              filters[k++] = ';';
              filters[k++] = '*';
            } else
              filters[k++] = p->extensions[j];
          }
          filters[k] = 0;
          patterns = wide(filters);
          free(filters);
        }
      }
      if (patterns) {
        COMDLG_FILTERSPEC specs[2] = {{L"Supported files", patterns},
                                      {L"All files", L"*.*"}};
        IFileOpenDialog_SetFileTypes(dialog, 2, specs);
      }
      HRESULT(WINAPI * item_from_path)(PCWSTR, IBindCtx *, REFIID, void **) =
          NULL;
      HMODULE shell = LoadLibraryW(L"shell32.dll");
      if (shell)
        item_from_path =
            (void *)GetProcAddress(shell, "SHCreateItemFromParsingName");
      IShellItem *item = NULL;
      if (folder && item_from_path &&
          SUCCEEDED(item_from_path(folder, NULL, &shell_id, (void **)&item))) {
        IFileOpenDialog_SetFolder(dialog, item);
        IShellItem_Release(item);
      }
      hr = InterlockedCompareExchange(&p->cancelled, 0, 0)
               ? HRESULT_FROM_WIN32(ERROR_CANCELLED)
               : IFileOpenDialog_Show(dialog, p->parent);
      state = hr == HRESULT_FROM_WIN32(ERROR_CANCELLED) ? 3 : 4;
      if (SUCCEEDED(hr) &&
          SUCCEEDED(IFileOpenDialog_GetResult(dialog, &item))) {
        PWSTR name = NULL;
        if (SUCCEEDED(
                IShellItem_GetDisplayName(item, SIGDN_FILESYSPATH, &name))) {
          int n =
              WideCharToMultiByte(CP_UTF8, 0, name, -1, NULL, 0, NULL, NULL);
          p->path = n ? malloc((size_t)n) : NULL;
          if (p->path) {
            WideCharToMultiByte(CP_UTF8, 0, name, -1, p->path, n, NULL, NULL);
            state = 2;
          }
          release(name);
        }
        IShellItem_Release(item);
      }
      free(title);
      free(folder);
      free(patterns);
      if (shell)
        FreeLibrary(shell);
      IFileOpenDialog_Release(dialog);
    }
    uninit();
  }
  FreeLibrary(lib);
  InterlockedExchange((LONG *)&p->state, state);
  return 0;
}
void *fortui_file_native_open(void *parent, int64_t xid, const char *title,
                              const char *folder, const char *extensions) {
  (void)xid;
  picker *p = calloc(1, sizeof *p);
  if (!p)
    return NULL;
  p->state = 1;
  p->parent = (HWND)parent;
  p->title = strdup(title);
  p->folder = strdup(folder);
  p->extensions = strdup(extensions);
  if (p->title && p->folder && p->extensions)
    p->thread = CreateThread(NULL, 0, choose_file, p, 0, &p->thread_id);
  if (!p->thread) {
    free(p->title);
    free(p->folder);
    free(p->extensions);
    free(p);
    return NULL;
  }
  return p;
}
int fortui_file_native_poll(void *opaque) {
  picker *p = opaque;
  return p ? (int)InterlockedCompareExchange((LONG *)&p->state, 0, 0) : 5;
}
static BOOL CALLBACK close_window(HWND w, LPARAM unused) {
  (void)unused;
  PostMessageW(w, WM_CLOSE, 0, 0);
  return TRUE;
}
void fortui_file_native_close(void *opaque) {
  picker *p = opaque;
  if (!p)
    return;
  InterlockedExchange(&p->cancelled, 1);
  /* Show owns the worker's modal loop. Close its windows before joining. */
  while (WaitForSingleObject(p->thread, 20) == WAIT_TIMEOUT)
    EnumThreadWindows(p->thread_id, close_window, 0);
  CloseHandle(p->thread);
  free(p->title);
  free(p->folder);
  free(p->extensions);
  free(p->path);
  free(p);
}
#elif defined(__APPLE__)
#include <dlfcn.h>
typedef void *object;
static object (*get_class)(const char *);
static void *(*selector)(const char *);
static void *message;
#define M0(o, s) ((object (*)(object, void *))message)(o, selector(s))
#define M1(o, s, a)                                                            \
  ((object (*)(object, void *, const void *))message)(o, selector(s), a)
#define BOOL1(o, s, b)                                                         \
  ((void (*)(object, void *, signed char))message)(o, selector(s), b)
typedef struct {
  int state;
  char *path;
  object panel;
  int references;
} picker;
typedef struct {
  unsigned long reserved, size;
} block_descriptor;
typedef struct {
  void *isa;
  int flags, reserved;
  void (*invoke)(void *, long);
  block_descriptor *descriptor;
  picker *request;
} completion_block;
static void release_picker(picker *p) {
  if (!--p->references) {
    free(p->path);
    free(p);
  }
}
static object string(const char *s) {
  return M1(get_class("NSString"), "stringWithUTF8String:", s);
}
static void completed(void *opaque, long result) {
  picker *p = ((completion_block *)opaque)->request;
  p->state = result == 1 ? 4 : 3;
  if (result == 1) {
    object url = M0(p->panel, "URL"), path = url ? M0(url, "path") : NULL;
    const char *s = path ? M0(path, "UTF8String") : NULL;
    if (s && (p->path = strdup(s)))
      p->state = 2;
  }
  M0(p->panel, "release");
  p->panel = NULL;
  release_picker(p);
}
void *fortui_file_native_open(void *parent, int64_t xid, const char *title,
                              const char *folder, const char *extensions) {
  (void)xid;
  if (!parent)
    return NULL;
  static void *appkit, *uniform_types;
  if (!appkit)
    appkit =
        dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_NOW);
  if (!appkit)
    return NULL;
  if (!uniform_types)
    uniform_types =
        dlopen("/System/Library/Frameworks/UniformTypeIdentifiers.framework/"
               "UniformTypeIdentifiers",
               RTLD_NOW);
  get_class = dlsym(RTLD_DEFAULT, "objc_getClass");
  selector = dlsym(RTLD_DEFAULT, "sel_registerName");
  message = dlsym(RTLD_DEFAULT, "objc_msgSend");
  void *block_class = dlsym(RTLD_DEFAULT, "_NSConcreteStackBlock");
  if (!get_class || !selector || !message || !block_class)
    return NULL;
  picker *p = calloc(1, sizeof *p);
  if (!p)
    return NULL;
  p->state = 1;
  p->references = 2;
  p->panel = M0(M0(get_class("NSOpenPanel"), "openPanel"), "retain");
  if (!p->panel) {
    free(p);
    return NULL;
  }
  M1(p->panel, "setTitle:", string(title));
  BOOL1(p->panel, "setCanChooseFiles:", 1);
  BOOL1(p->panel, "setCanChooseDirectories:", 0);
  BOOL1(p->panel, "setAllowsMultipleSelection:", 0);
  BOOL1(p->panel, "setAllowsOtherFileTypes:", 1);
  object url = M1(get_class("NSURL"), "fileURLWithPath:", string(folder));
  if (url)
    M1(p->panel, "setDirectoryURL:", url);
  if (*extensions) {
    object types = M0(get_class("NSMutableArray"), "array");
    char *copy = strdup(extensions), *at = copy;
    if (copy) {
      object type_class = get_class("UTType");
      while (at) {
        char *end = strchr(at, ',');
        if (end)
          *end = 0;
        if (*at == '.')
          ++at;
        if (*at) {
          object type =
              type_class
                  ? M1(type_class, "typeWithFilenameExtension:", string(at))
                  : string(at);
          if (type)
            M1(types, "addObject:", type);
        }
        at = end ? end + 1 : NULL;
      }
      M1(p->panel,
         type_class ? "setAllowedContentTypes:" : "setAllowedFileTypes:",
         types);
      free(copy);
    }
  }
  static block_descriptor descriptor = {0, sizeof(completion_block)};
  completion_block block = {block_class, 0, 0, completed, &descriptor, p};
  ((void (*)(object, void *, object, void *))message)(
      p->panel, selector("beginSheetModalForWindow:completionHandler:"), parent,
      &block);
  return p;
}
int fortui_file_native_poll(void *opaque) {
  return opaque ? ((picker *)opaque)->state : 5;
}
void fortui_file_native_close(void *opaque) {
  picker *p = opaque;
  if (!p)
    return;
  if (p->state == 1 && p->panel)
    M1(p->panel, "cancel:", NULL);
  release_picker(p);
}
#else
/* Browser file access remains in its trusted JavaScript activation handler. */
typedef struct {
  int state;
  char *path;
} picker;
void *fortui_file_native_open(void *parent, int64_t xid, const char *title,
                              const char *folder, const char *extensions) {
  (void)parent;
  (void)xid;
  (void)title;
  (void)folder;
  (void)extensions;
  return NULL;
}
int fortui_file_native_poll(void *p) {
  (void)p;
  return 5;
}
void fortui_file_native_close(void *p) { (void)p; }
#endif

int fortui_file_native_result(void *opaque, char *out, int capacity) {
  picker *p = opaque;
  if (!p || !p->path)
    return -1;
  size_t n = strlen(p->path);
  if (n > INT32_MAX - 1)
    return -1;
  if (out && capacity > (int)n)
    memcpy(out, p->path, n + 1);
  return (int)n;
}
