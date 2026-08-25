#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static volatile int g_playPressed = 0;

@interface REVCLauncherTap : NSObject
+ (REVCLauncherTap *)shared;
- (void)playTapped;
@end

@implementation REVCLauncherTap
+ (REVCLauncherTap *)shared {
	static REVCLauncherTap *s;
	if (!s) s = [[REVCLauncherTap alloc] init];
	return s;
}
- (void)playTapped {
	g_playPressed = 1;
}
@end

static UIImage *
LoadLauncherImg(NSString *name)
{
	NSString *p = [[NSBundle mainBundle] pathForResource:name
	                                              ofType:nil
	                                                 inDirectory:@"launcher"];
	if (!p)
		p = [[NSBundle mainBundle] pathForResource:name ofType:nil];
	return p ? [UIImage imageWithContentsOfFile:p] : nil;
}

extern "C" void
ios_show_launcher(void *sdlwindow)
{
	@autoreleasepool {
		SDL_Window *win = (SDL_Window *)sdlwindow;
		SDL_SysWMinfo wmi;
		memset(&wmi, 0, sizeof(wmi));
		SDL_VERSION(&wmi.version);
		if (!SDL_GetWindowWMInfo(win, &wmi))
			return;
		UIWindow *uiw = (__bridge UIWindow *)wmi.info.uikit.window;
		UIView *root = uiw.rootViewController.view;
		if (!root)
			return;
		[root layoutIfNeeded];

		CGRect b = root.bounds;
		CGFloat W = b.size.width, H = b.size.height;

		UIView *launch = [[UIView alloc] initWithFrame:b];
		launch.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		launch.backgroundColor = [UIColor blackColor];
		launch.tag = 777001;

		// background art (1:1 from the NORMSOURCE launcher)
		UIImage *bgImg = LoadLauncherImg(@"launcher_home_background.webp");
		if (bgImg) {
			UIImageView *bg = [[UIImageView alloc] initWithImage:bgImg];
			bg.frame = b;
			bg.contentMode = UIViewContentModeScaleAspectFill;
			bg.clipsToBounds = YES;
			bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			[launch addSubview:bg];

			// dark fade at the bottom so buttons read well
			UIImageView *fade = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_home_info_bg.webp")];
			fade.frame = CGRectMake(0, H * 0.55, W, H * 0.45);
			fade.contentMode = UIViewContentModeScaleToFill;
			fade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			[launch addSubview:fade];
		}

		// logo
		UIImage *logoImg = LoadLauncherImg(@"logo.png");
		if (logoImg) {
			CGFloat lw = W * 0.5;
			UIImageView *logo = [[UIImageView alloc] initWithImage:logoImg];
			logo.frame = CGRectMake((W - lw) / 2.0, H * 0.06, lw, lw * (logoImg.size.height / logoImg.size.width));
			logo.contentMode = UIViewContentModeScaleAspectFit;
			logo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			[launch addSubview:logo];
		}

		// server panel (name bg + text), like the CRMP launcher server row
		UIImage *nameBg = LoadLauncherImg(@"launcher_home_name_bg.webp");
		CGFloat panelW = W * 0.86, panelH = 64.0;
		CGFloat panelX = (W - panelW) / 2.0, panelY = H * 0.60;
		UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelW, panelH)];
		if (nameBg) {
			UIImageView *nb = [[UIImageView alloc] initWithImage:nameBg];
			nb.frame = panel.bounds;
			nb.contentMode = UIViewContentModeScaleToFill;
			nb.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			[panel addSubview:nb];
		} else {
			panel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
			panel.layer.cornerRadius = 10.0;
		}
		UILabel *srvName = [[UILabel alloc] initWithFrame:CGRectMake(14, 8, panelW - 28, 24)];
		srvName.text = @"STAGE MOBILE";
		srvName.textColor = [UIColor whiteColor];
		srvName.font = [UIFont boldSystemFontOfSize:19];
		[panel addSubview:srvName];
		UILabel *srvInfo = [[UILabel alloc] initWithFrame:CGRectMake(14, 34, panelW - 28, 20)];
		srvInfo.text = @"Server 1  •  Online";
		srvInfo.textColor = [UIColor colorWithRed:0.55 green:0.85 blue:0.4 alpha:1.0];
		srvInfo.font = [UIFont systemFontOfSize:14];
		[panel addSubview:srvInfo];
		[launch addSubview:panel];

		// PLAY button (the NORMSOURCE play button art)
		UIImage *playImg = LoadLauncherImg(@"launcher_home_play.webp");
		CGFloat btnW = panelW, btnH = 84.0;
		UIButton *play = [UIButton buttonWithType:UIButtonTypeCustom];
		play.frame = CGRectMake(panelX, panelY + panelH + 18, btnW, btnH);
		if (playImg)
			[play setBackgroundImage:playImg forState:UIControlStateNormal];
		else
			play.backgroundColor = [UIColor colorWithRed:0.85 green:0.65 blue:0.1 alpha:1.0];
		[play setTitle:@"ИГРАТЬ" forState:UIControlStateNormal];
		[play setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
		play.titleLabel.font = [UIFont boldSystemFontOfSize:30];
		play.layer.cornerRadius = 12.0;
		play.clipsToBounds = YES;
		[play addTarget:[REVCLauncherTap shared]
		            action:@selector(playTapped)
		  forControlEvents:UIControlEventTouchUpInside];
		[launch addSubview:play];

		// socials row
		NSArray *socials = @[ @"launcher_home_vk.webp", @"launcher_home_tg.webp", @"launcher_home_web.webp" ];
		CGFloat sw = 44.0, gap = 18.0;
		CGFloat totalW = socials.count * sw + (socials.count - 1) * gap;
		for (NSUInteger i = 0; i < socials.count; i++) {
			UIButton *sb = [UIButton buttonWithType:UIButtonTypeCustom];
			sb.frame = CGRectMake((W - totalW) / 2.0 + i * (sw + gap), H - sw - 24, sw, sw);
			UIImage *sim = LoadLauncherImg(socials[i]);
			if (sim)
				[sb setImage:sim forState:UIControlStateNormal];
			else
				sb.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
			[launch addSubview:sb];
		}

		[root addSubview:launch];
		[root bringSubviewToFront:launch];
	}
}

extern "C" int
ios_play_pressed(void)
{
	// remove the launcher the moment play was pressed (caller resumes the game)
	if (g_playPressed) {
		dispatch_async(dispatch_get_main_queue(), ^{
			for (UIWindow *w in [UIApplication sharedApplication].windows) {
				UIView *v = [w viewWithTag:777001];
				if (v)
					[v removeFromSuperview];
			}
		});
		return 1;
	}
	return 0;
}
