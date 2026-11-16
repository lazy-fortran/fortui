#ifdef _WIN32
#include <stdlib.h>
int fortui_test_setenv(const char *name, const char *value, int overwrite) {
    if (!overwrite && getenv(name)) return 0;
    return _putenv_s(name, value);
}
int fortui_test_unsetenv(const char *name) { return _putenv_s(name, ""); }
#endif
