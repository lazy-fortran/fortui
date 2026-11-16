/* The desktop owns appearance schedules. Unknown preferences mean light. */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#ifdef _WIN32
#include <windows.h>
int fortui_system_appearance(void) {
    HMODULE lib = LoadLibraryW(L"advapi32.dll");
    if (!lib) return 0;
    typedef LSTATUS (WINAPI *read_t)(HKEY,LPCWSTR,LPCWSTR,DWORD,LPDWORD,PVOID,LPDWORD);
    read_t read = (read_t)GetProcAddress(lib, "RegGetValueW");
    DWORD light = 1, size = sizeof light;
    LONG rc = read ? read(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, &light, &size) : -1;
    FreeLibrary(lib);
    return rc == ERROR_SUCCESS ? (light ? 2 : 1) : 0;
}
#elif defined(__APPLE__)
#include <dlfcn.h>
int fortui_system_appearance(void) {
    static void *lib;
    if (!lib) lib = dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", RTLD_LAZY);
    if (!lib) return 0;
    void *(*cls)(const char *) = dlsym(RTLD_DEFAULT, "objc_getClass");
    void *(*sel)(const char *) = dlsym(RTLD_DEFAULT, "sel_registerName");
    void *(*msg)(void *, void *) = dlsym(RTLD_DEFAULT, "objc_msgSend");
    void *(*msg1)(void *, void *, const void *) = dlsym(RTLD_DEFAULT, "objc_msgSend");
    if (!cls || !sel || !msg) return 0;
    void *defaults = msg(cls("NSUserDefaults"), sel("standardUserDefaults"));
    void *key = msg1(cls("NSString"), sel("stringWithUTF8String:"), "AppleInterfaceStyle");
    void *value = msg1(defaults, sel("stringForKey:"), key);
    const char *name = value ? msg(value, sel("UTF8String")) : NULL;
    return name && strcmp(name, "Dark") == 0 ? 1 : 2;
}
#elif defined(__EMSCRIPTEN__)
/* Implemented by the browser host's matchMedia query. */
#else
#include <unistd.h>
#include <sys/wait.h>
#include <poll.h>
#include <signal.h>
#include <fcntl.h>
static int portal(void) {
    int p[2], status;
    char buf[256] = {0};
    if (pipe(p) != 0) return 0;
    pid_t pid = fork();
    if (pid == 0) {
        dup2(p[1], STDOUT_FILENO);
        int null = open("/dev/null", O_WRONLY);
        if (null >= 0) dup2(null, STDERR_FILENO);
        close(p[0]); close(p[1]);
        execlp("gdbus", "gdbus", "call", "--session", "--timeout", "1",
            "--dest", "org.freedesktop.portal.Desktop", "--object-path",
            "/org/freedesktop/portal/desktop", "--method",
            "org.freedesktop.portal.Settings.Read", "org.freedesktop.appearance",
            "color-scheme", (char *)NULL);
        _exit(127);
    }
    close(p[1]);
    if (pid < 0) { close(p[0]); return 0; }
    struct pollfd fd = {p[0], POLLIN, 0};
    if (poll(&fd, 1, 250) > 0) {
        ssize_t n = read(p[0], buf, sizeof buf - 1);
        if (n < 0) buf[0] = 0;
    }
    close(p[0]);
    if (waitpid(pid, &status, WNOHANG) == 0) {
        kill(pid, SIGKILL); waitpid(pid, &status, 0);
    }
    char *v = strstr(buf, "uint32 ");
    if (!v) return 0;
    int value = atoi(v + 7);
    return value == 1 || value == 2 ? value : 0;
}
static int has_dark(const char *name) {
    char lower[1024];
    size_t n = strlen(name);
    if (n >= sizeof lower) n = sizeof lower - 1;
    for (size_t i = 0; i < n; ++i) lower[i] = (char)tolower((unsigned char)name[i]);
    lower[n] = 0;
    return strstr(lower, "dark") != NULL;
}
int fortui_system_appearance(void) {
    int value = portal();
    if (value) return value;
    const char *gtk = getenv("GTK_THEME");
    if (gtk && *gtk) return has_dark(gtk) ? 1 : 2;
    const char *base = getenv("XDG_CONFIG_HOME"), *home = getenv("HOME");
    char dir[2048], path[2300], line[2048];
    if (base && *base) snprintf(dir, sizeof dir, "%s", base);
    else if (home) snprintf(dir, sizeof dir, "%s/.config", home);
    else return 0;
    snprintf(path, sizeof path, "%s/gtk-3.0/settings.ini", dir);
    FILE *f = fopen(path, "r");
    int named = 0;
    if (f) {
        while (fgets(line, sizeof line, f)) {
            if (strstr(line, "gtk-application-prefer-dark-theme") &&
                (strstr(line, "=1") || strstr(line, "=true") || strstr(line, "= true"))) {
                fclose(f); return 1;
            }
            if (strstr(line, "gtk-theme-name")) named = has_dark(line) ? 1 : 2;
        }
        fclose(f);
        if (named) return named;
    }
    snprintf(path, sizeof path, "%s/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml", dir);
    f = fopen(path, "r");
    if (f) {
        while (fgets(line, sizeof line, f)) {
            if (strstr(line, "name=\"ThemeName\"")) {
                value = has_dark(line) ? 1 : 2; break;
            }
        }
        fclose(f);
    }
    return value;
}
#endif
