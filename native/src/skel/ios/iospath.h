#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Path of the app bundle resources (read-only, game data lives here) */
const char *ios_resource_path(void);

/* Writable Documents directory (saves, settings) */
const char *ios_documents_path(void);

#ifdef __cplusplus
}
#endif
