#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <math.h>

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

// rounded rect + optional stroke, replicates the android vector drawables
static UIView *
PanelRect(CGRect frame, UIColor *fill, CGFloat radius, UIColor *stroke, CGFloat strokeWidth)
{
	UIView *v = [[UIView alloc] initWithFrame:frame];
	v.backgroundColor = fill;
	v.layer.cornerRadius = radius;
	v.clipsToBounds = YES;
	if (stroke) {
		v.layer.borderColor = stroke.CGColor;
		v.layer.borderWidth = strokeWidth;
	}
	v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	return v;
}

static UILabel *
Label(CGRect frame, NSString *text, CGFloat size, UIColor *color, BOOL bold, BOOL center)
{
	UILabel *l = [[UILabel alloc] initWithFrame:frame];
	l.text = text;
	l.textColor = color;
	l.font = [UIFont systemFontOfSize:size weight:bold ? UIFontWeightBold : UIFontWeightRegular];
	l.textAlignment = center ? NSTextAlignmentCenter : NSTextAlignmentLeft;
	l.adjustsFontSizeToFitWidth = YES;
	l.minimumScaleFactor = 0.6;
	l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	return l;
}

// social icon: rounded square with brand color and glyph text
static UIView *
SocialIcon(CGRect frame, UIColor *color, NSString *glyph)
{
	UIView *v = [[UIView alloc] initWithFrame:frame];
	v.backgroundColor = color;
	v.layer.cornerRadius = frame.size.height * 0.22;
	v.clipsToBounds = YES;
	UILabel *l = Label(v.bounds, glyph, frame.size.height * 0.42, [UIColor whiteColor], YES, YES);
	l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[v addSubview:l];
	return v;
}

extern "C" void
ios_show_launcher(void *uiwindow)
{
	@autoreleasepool {
		UIWindow *uiw = (__bridge UIWindow *)uiwindow;
		UIView *root = uiw.rootViewController.view;
		if (!root)
			return;
		[root layoutIfNeeded];

		CGRect b = root.bounds;
		CGFloat W = b.size.width, H = b.size.height;
		// sdp scale: android design width is 390dp
		CGFloat S = W / 390.0;

		UIView *launch = [[UIView alloc] initWithFrame:b];
		launch.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		launch.backgroundColor = [UIColor blackColor];
		launch.tag = 777001;

		// 1) full screen background art
		UIImage *bgImg = LoadLauncherImg(@"launcher_main_bg.webp");
		if (bgImg) {
			UIImageView *bg = [[UIImageView alloc] initWithImage:bgImg];
			bg.frame = b;
			bg.contentMode = UIViewContentModeScaleAspectFill;
			bg.clipsToBounds = YES;
			bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			[launch addSubview:bg];
		}

		// 2) left fade strip (28.12% width, full height)
		UIImage *fadeImg = LoadLauncherImg(@"launcher_main_fade.webp");
		if (fadeImg) {
			UIImageView *fade = [[UIImageView alloc] initWithImage:fadeImg];
			fade.frame = CGRectMake(0, 0, W * 0.2812, H);
			fade.contentMode = UIViewContentModeScaleToFill;
			fade.autoresizingMask = UIViewAutoresizingFlexibleHeight;
			[launch addSubview:fade];
		}

		// 3) login fade top-right (20.72% x 16.48%)
		UIImage *loginFade = LoadLauncherImg(@"launcher_main_login_fade.webp");
		if (loginFade) {
			UIImageView *lf = [[UIImageView alloc] initWithImage:loginFade];
			lf.frame = CGRectMake(W - W * 0.2072, 0, W * 0.2072, H * 0.1648);
			lf.contentMode = UIViewContentModeScaleToFill;
			lf.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth;
			[launch addSubview:lf];
		}

		// 4) socials bottom-left (10.55%H squares, biases from the xml)
		CGFloat socSize = H * 0.1055;
		struct { CGFloat hb; NSString *glyph; UIColor *color; } socs[] = {
			{ 0.021, @"YT", [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0] },
			{ 0.093, @"VK", [UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:1.0] },
			{ 0.166, @"TG", [UIColor colorWithRed:0.16 green:0.67 blue:0.93 alpha:1.0] },
		};
		for (int i = 0; i < 3; i++) {
			CGRect fr = CGRectMake(socs[i].hb * (W - socSize), 0.9554 * (H - socSize), socSize, socSize);
			[launch addSubview:SocialIcon(fr, socs[i].color, socs[i].glyph)];
		}

		// 5) account panel top-right (35%W x 10%H)
		{
			CGFloat pw = W * 0.35, ph = H * 0.10;
			UIView *acc = [[UIView alloc] initWithFrame:CGRectMake(W - pw, 0, pw, ph)];

			// shield placeholder (rounded rect) at the right
			CGFloat shH = ph * 0.6, shW = shH * 0.8;
			UIView *shield = PanelRect(CGRectMake(pw - shW - 6, (ph - shH) / 2, shW, shH),
				[UIColor colorWithWhite:1.0 alpha:0.15], 6, [UIColor colorWithWhite:1.0 alpha:0.4], 1);
			[acc addSubview:shield];

			// account circle icon left of the shield
			CGFloat icH = ph * 0.5;
			UIView *ic = [[UIView alloc] initWithFrame:CGRectMake(pw - shW - 6 - 6 - icH, (ph - icH) / 2, icH, icH)];
			ic.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
			ic.layer.cornerRadius = icH / 2;
			[acc addSubview:ic];

			UILabel *title = Label(CGRectMake(0, ph * 0.16, pw - shW - 6 - 6 - icH - 8, ph * 0.3),
				@"ВАШ АККАУНТ", 8 * S, [UIColor colorWithWhite:1.0 alpha:0.5], YES, NO);
			title.textAlignment = NSTextAlignmentRight;
			[acc addSubview:title];
			UILabel *name = Label(CGRectMake(0, ph * 0.45, pw - shW - 6 - 6 - icH - 8, ph * 0.4),
				@"Denny_Walker", 10 * S, [UIColor whiteColor], YES, NO);
			name.textAlignment = NSTextAlignmentRight;
			[acc addSubview:name];

			acc.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth;
			[launch addSubview:acc];
		}

		// 6) "ВЫБОР СЕРВЕРА" title
		[launch addSubview:Label(CGRectMake(W * 0.023, H * 0.04 - 7 * S, W * 0.1843, 14 * S),
			@"ВЫБОР СЕРВЕРА", 10 * S, [UIColor whiteColor], YES, NO)];

		// change-server icon (swap glyph)
		UILabel *swap = Label(CGRectMake(W * 0.023 + W * 0.226 - 20 * S, H * 0.0444 - 8 * S, 20 * S, 16 * S),
			@"⇄", 14 * S, [UIColor whiteColor], YES, YES);
		[launch addSubview:swap];

		// 7) current server panel (22.6%W x 13.88%H)
		{
			CGFloat pw = W * 0.226, ph = H * 0.1388;
			CGFloat px = W * 0.023;
			CGFloat py = 0.108 * (H - ph);
			UIView *panel = PanelRect(CGRectMake(px, py, pw, ph),
				[UIColor colorWithRed:0 green:0 blue:0 alpha:0.03], (32.79 / 546.0) * pw,
				[UIColor colorWithWhite:1.0 alpha:0.22], 2);

			// gold "#1" badge
			UIImage *goldImg = LoadLauncherImg(@"launcher_servers_item_gold_bg.webp");
			CGFloat bdW = pw * 0.265;
			UIView *badge;
			if (goldImg) {
				badge = [[UIImageView alloc] initWithImage:goldImg];
				badge.frame = CGRectMake(pw * 0.06, (ph - bdW) / 2, bdW, bdW);
				badge.contentMode = UIViewContentModeScaleToFill;
			} else {
				badge = PanelRect(CGRectMake(pw * 0.06, (ph - bdW) / 2, bdW, bdW),
					[UIColor colorWithRed:0.95 green:0.8 blue:0.2 alpha:1.0], bdW / 2, nil, 0);
			}
			[badge addSubview:Label(badge.bounds, @"#1", 12 * S, [UIColor colorWithRed:0.3 green:0.27 blue:0.04 alpha:1.0], YES, YES)];
			[panel addSubview:badge];

			// server name + load caption on the right side
			UILabel *nm = Label(CGRectMake(pw * 0.36, ph * 0.14, pw * 0.6, ph * 0.28),
				@"STAGE MOBILE", 9 * S, [UIColor whiteColor], YES, NO);
			[panel addSubview:nm];
			UILabel *cap = Label(CGRectMake(pw * 0.36, ph * 0.44, pw * 0.6, ph * 0.2),
				@"ЗАГРУЖЕННОСТЬ СЕРВЕРА", 6 * S, [UIColor colorWithWhite:1.0 alpha:0.5], YES, NO);
			[panel addSubview:cap];

			// progress bar (30% loaded, green fill)
			CGFloat pbW = pw * 0.288, pbH = H * 0.0466;
			CGFloat pbX = 0.51 * (pw - pbW), pbY = 0.83 * (ph - pbH);
			UIView *track = PanelRect(CGRectMake(pbX, pbY, pbW, pbH),
				[UIColor colorWithWhite:1.0 alpha:0.2], 4 * S, nil, 0);
			UIView *fill = PanelRect(CGRectMake(0, 0, pbW * 0.3, pbH),
				[UIColor colorWithRed:0.62 green:1.0 blue:0.38 alpha:1.0], 4 * S, nil, 0);
			[track addSubview:fill];
			[panel addSubview:track];
			UILabel *busy = Label(CGRectMake(pbX + pbW + 4 * S, pbY - 2 * S, pw - (pbX + pbW + 4 * S) - 6 * S, pbH + 4 * S),
				@"ВЫСОКАЯ", 7 * S, [UIColor whiteColor], YES, NO);
			[panel addSubview:busy];

			[launch addSubview:panel];
		}

		// 8) PLAY button bottom-right (20.31%W x 14.81%H), green gradient
		{
			CGFloat bw = W * 0.2031, bh = H * 0.1481;
			CGFloat bx = 0.9739 * (W - bw), by = 0.9565 * (H - bh);
			UIButton *play = [UIButton buttonWithType:UIButtonTypeCustom];
			play.frame = CGRectMake(bx, by, bw, bh);

			// gradient layer replicating launcher_main_play_btn vector
			CAGradientLayer *grad = [CAGradientLayer layer];
			grad.frame = play.bounds;
			grad.colors = @[
				(id)[UIColor colorWithRed:0x76/255.0 green:0xf8/255.0 blue:0x10/255.0 alpha:1.0].CGColor,
				(id)[UIColor colorWithRed:0xd1/255.0 green:0xff/255.0 blue:0x6f/255.0 alpha:1.0].CGColor ];
			grad.startPoint = CGPointMake(0.0, 1.0);
			grad.endPoint = CGPointMake(0.35, 0.0);
			grad.cornerRadius = (35.0 / 390.0) * bw;
			grad.masksToBounds = YES;
			[play.layer insertSublayer:grad atIndex:0];

			[play setTitle:@"ИГРАТЬ" forState:UIControlStateNormal];
			[play setTitleColor:[UIColor colorWithRed:0x38/255.0 green:0x62/255.0 blue:0x1a/255.0 alpha:1.0]
			               forState:UIControlStateNormal];
			play.titleLabel.font = [UIFont boldSystemFontOfSize:23 * S];
			play.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
			[play addTarget:[REVCLauncherTap shared]
			           action:@selector(playTapped)
			 forControlEvents:UIControlEventTouchUpInside];
			[launch addSubview:play];
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
