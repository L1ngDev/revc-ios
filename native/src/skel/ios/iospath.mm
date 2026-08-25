#import <Foundation/Foundation.h>
#import <unistd.h>
#import <string>
#import <cstdarg>
#import <cstdio>
#import <cstring>
#import <csignal>
#import <ctime>
#import <execinfo.h>
#import <dlfcn.h>

extern "C" const char *
ios_resource_path(void)
{
	static std::string path;
	if (path.empty()) {
		NSString *res = [[NSBundle mainBundle] resourcePath];
		path = res ? std::string([res UTF8String]) : std::string(".");
	}
	return path.c_str();
}

extern "C" const char *
ios_documents_path(void)
{
	static std::string path;
	if (path.empty()) {
		NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		path = (dirs.count > 0) ? std::string([dirs[0] UTF8String]) : std::string(".");
	}
	return path.c_str();
}

static FILE *g_logFile = nil;

extern "C" void
ios_log_open(void)
{
	if (g_logFile)
		return;
	char p[1024];
	snprintf(p, sizeof(p), "%s/gamelog.txt", ios_documents_path());
	g_logFile = fopen(p, "w");
	if (g_logFile) {
		time_t t = time(nil);
		char tb[32];
		strftime(tb, sizeof(tb), "%Y-%m-%d %H:%M:%S", localtime(&t));
		fprintf(g_logFile, "==== gamelog started %s ====\n", tb);
		fflush(g_logFile);
	}
}

extern "C" void
ios_log(const char *fmt, ...)
{
	if (!g_logFile)
		ios_log_open();
	if (!g_logFile)
		return;

	time_t t = time(nil);
	char tb[16];
	strftime(tb, sizeof(tb), "%H:%M:%S", localtime(&t));
	fprintf(g_logFile, "[%s] ", tb);

	va_list ap;
	va_start(ap, fmt);
	vfprintf(g_logFile, fmt, ap);
	va_end(ap);

	fputc('\n', g_logFile);
	fflush(g_logFile);
}

extern "C" void
ios_log_raw(const char *s)
{
	if (!g_logFile)
		ios_log_open();
	if (!g_logFile)
		return;
	fprintf(g_logFile, "%s\n", s);
	fflush(g_logFile);
}

static void
ios_dump_backtrace(void *ctx)
{
	if (!g_logFile)
		return;
	void *bt[64];
	int n = backtrace(bt, 64);
	fprintf(g_logFile, "---- backtrace (%d frames) ----\n", n);
	char **syms = backtrace_symbols(bt, n);
	for (int i = 0; i < n; i++) {
		// try to compute module-relative offset for later symbolication
		Dl_info info;
		if (dladdr(bt[i], &info) && info.dli_fname) {
			const char *base = strrchr(info.dli_fname, '/');
			base = base ? base + 1 : info.dli_fname;
			unsigned long off = (unsigned long)bt[i] - (unsigned long)info.dli_fbase;
			if (info.dli_sname)
				fprintf(g_logFile, "#%02d %s  (%s + 0x%lx)  %s\n", i, syms ? syms[i] : "?", base, off, info.dli_sname);
			else
				fprintf(g_logFile, "#%02d %s  (%s + 0x%lx)\n", i, syms ? syms[i] : "?", base, off);
		} else {
			fprintf(g_logFile, "#%02d %s\n", i, syms ? syms[i] : "?");
		}
	}
	free(syms);
	if (ctx)
		fprintf(g_logFile, "(ucontext available)\n");
	fflush(g_logFile);
}

static void
ios_signal_handler(int signum, siginfo_t *info, void *ctx)
{
	if (g_logFile) {
		fprintf(g_logFile, "\n!!!! CRASH: signal %d at address %p !!!!\n", signum, info ? info->si_addr : nil);
		ios_dump_backtrace(ctx);
		fprintf(g_logFile, "!!!! end of crash report !!!!\n");
		fflush(g_logFile);
		fclose(g_logFile);
		g_logFile = nil;
	}
	// restore default and re-raise so the OS still generates its own report
	signal(signum, SIG_DFL);
	raise(signum);
}

static void
ios_ns_exception_handler(NSException *exception)
{
	if (g_logFile) {
		fprintf(g_logFile, "\n!!!! NSException: %s !!!!\n", exception.name.UTF8String);
		fprintf(g_logFile, "reason: %s\n", exception.reason ? exception.reason.UTF8String : "?");
		NSString *stack = exception.callStackSymbols ? [exception.callStackSymbols componentsJoinedByString:@"\n"] : nil;
		fprintf(g_logFile, "call stack:\n%s\n", stack ? stack.UTF8String : "?");
		fflush(g_logFile);
		fclose(g_logFile);
		g_logFile = nil;
	}
}

extern "C" void
ios_install_crash_handler(void)
{
	NSSetUncaughtExceptionHandler(ios_ns_exception_handler);

	// alternate signal stack so we survive stack overflows too
	static char sigstack[SIGSTKSZ * 4];
	stack_t ss;
	ss.ss_sp = sigstack;
	ss.ss_size = sizeof(sigstack);
	ss.ss_flags = 0;
	sigaltstack(&ss, nil);

	struct sigaction act;
	memset(&act, 0, sizeof(act));
	act.sa_sigaction = ios_signal_handler;
	act.sa_flags = SA_SIGINFO | SA_ONSTACK;
	const int sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP };
	for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++)
		sigaction(sigs[i], &act, nil);

	// heartbeat: proves the process is alive even if the main thread hangs
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
		static int beat = 0;
		while (true) {
			[NSThread sleepForTimeInterval:5.0];
			ios_log("heartbeat %d", ++beat);
		}
	});
}
