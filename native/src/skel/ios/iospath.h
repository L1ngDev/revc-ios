#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Path of the app bundle resources (read-only, game data lives here) */
const char *ios_resource_path(void);

/* Writable Documents directory (saves, settings) */
const char *ios_documents_path(void);

/* Open Documents/gamelog.txt for appending (call once at startup) */
void ios_log_open(void);

/* Append a line to gamelog.txt (printf-style) and flush */
void ios_log(const char *fmt, ...);

/* Append a raw string + newline to gamelog.txt and flush */
void ios_log_raw(const char *s);

/* Install signal + NSException handlers that dump a backtrace to gamelog.txt */
void ios_install_crash_handler(void);

/* Show the NORMSOURCE-style launcher UI over the SDL window (blocking flag inside) */
void ios_show_launcher(void *sdlwindow);

/* Returns 1 once the user pressed PLAY in the launcher */
int ios_play_pressed(void);

#ifdef __cplusplus
}
#endif
