#include <lean/lean.h>
#include <stdint.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#endif

/* GetFileAttributesW inspects the link itself. Reject every reparse tag,
   including junctions; no target content is opened by this check. */
LEAN_EXPORT uint32_t mirrors_path_reparse_status(b_lean_obj_arg path) {
#ifdef _WIN32
    const char *utf8 = lean_string_cstr(path);
    size_t bytes = lean_string_size(path) - 1;
    if (bytes == 0 || bytes > INT_MAX || strlen(utf8) != bytes) return 3;
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                   utf8, (int)bytes, NULL, 0);
    if (count <= 0) return 3;
    wchar_t *wide = malloc(((size_t)count + 1) * sizeof(wchar_t));
    if (!wide) return 3;
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, (int)bytes,
                            wide, count) != count) { free(wide); return 3; }
    wide[count] = 0;
    DWORD attributes = GetFileAttributesW(wide);
    DWORD error = attributes == INVALID_FILE_ATTRIBUTES ? GetLastError() : 0;
    free(wide);
    if (attributes == INVALID_FILE_ATTRIBUTES)
        return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ? 2 : 3;
    return (attributes & FILE_ATTRIBUTE_REPARSE_POINT) ? 1 : 0;
#else
    (void)path;
    return 0;
#endif
}
