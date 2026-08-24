#import <Foundation/Foundation.h>
#import <unistd.h>
#import <string>

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
