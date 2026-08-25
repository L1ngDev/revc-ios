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
	l.font = [UIFont systemFontOfSize:size weight:bold ? UIFontWeightHeavy : UIFontWeightRegular];
	l.textAlignment = center ? NSTextAlignmentCenter : NSTextAlignmentLeft;
	l.adjustsFontSizeToFitWidth = YES;
	l.minimumScaleFactor = 0.5;
	l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	return l;
}

// YouTube: white rounded-rect play glyph on a dark translucent square
static UIView *
YouTubeIcon(CGRect frame)
{
	UIView *v = [[UIView alloc] initWithFrame:frame];
	v.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.55];
	v.layer.cornerRadius = frame.size.height * 0.24;
	v.clipsToBounds = YES;

	UIView *screen = [[UIView alloc] initWithFrame:CGRectMake(frame.size.width * 0.20, frame.size.height * 0.31,
		frame.size.width * 0.60, frame.size.height * 0.38)];
	screen.backgroundColor = [UIColor whiteColor];
	screen.layer.cornerRadius = screen.frame.size.height * 0.30;
	[v addSubview:screen];

	UIBezierPath *tri = [UIBezierPath bezierPath];
	CGFloat cx = frame.size.width / 2, cy = frame.size.height / 2;
	CGFloat s = frame.size.height * 0.095;
	[tri moveToPoint:CGPointMake(cx - s * 0.85, cy - s)];
	[tri addLineToPoint:CGPointMake(cx - s * 0.85, cy + s)];
	[tri addLineToPoint:CGPointMake(cx + s * 1.05, cy)];
	[tri closePath];
	CAShapeLayer *sl = [CAShapeLayer layer];
	sl.path = tri.CGPath;
	sl.fillColor = [UIColor colorWithWhite:0.08 alpha:1.0].CGColor;
	[screen.layer addSublayer:sl];
	return v;
}

// VK: white VK logo on a dark translucent square
static UIView *
VKIcon(CGRect frame)
{
	UIView *v = [[UIView alloc] initWithFrame:frame];
	v.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.55];
	v.layer.cornerRadius = frame.size.height * 0.24;
	v.clipsToBounds = YES;
	[v addSubview:Label(v.bounds, @"VK", frame.size.height * 0.36, [UIColor whiteColor], YES, YES)];
	return v;
}

// Telegram: white paper plane on a dark translucent square
static UIView *
TGIcon(CGRect frame)
{
	UIView *v = [[UIView alloc] initWithFrame:frame];
	v.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.55];
	v.layer.cornerRadius = frame.size.height * 0.24;
	v.clipsToBounds = YES;

	UIBezierPath *plane = [UIBezierPath bezierPath];
	CGFloat w = frame.size.width, h = frame.size.height;
	[plane moveToPoint:CGPointMake(w * 0.18, h * 0.52)];
	[plane addLineToPoint:CGPointMake(w * 0.82, h * 0.25)];
	[plane addLineToPoint:CGPointMake(w * 0.63, h * 0.77)];
	[plane addLineToPoint:CGPointMake(w * 0.45, h * 0.59)];
	[plane addLineToPoint:CGPointMake(w * 0.18, h * 0.52)];
	[plane closePath];
	CAShapeLayer *pl = [CAShapeLayer layer];
	pl.path = plane.CGPath;
	pl.fillColor = [UIColor whiteColor].CGColor;
	[v.layer addSublayer:pl];

	UIBezierPath *fold = [UIBezierPath bezierPath];
	[fold moveToPoint:CGPointMake(w * 0.45, h * 0.59)];
	[fold addLineToPoint:CGPointMake(w * 0.82, h * 0.25)];
	[fold addLineToPoint:CGPointMake(w * 0.50, h * 0.68)];
	[fold closePath];
	CAShapeLayer *fl = [CAShapeLayer layer];
	fl.path = fold.CGPath;
	fl.fillColor = [UIColor colorWithWhite:0.82 alpha:1.0].CGColor;
	[v.layer addSublayer:fl];
	return v;
}

// Gold account badge: gold circle + white person silhouette
static UIView *
AccountIcon(CGRect frame)
{
	UIView *v = [[UIView alloc] initWithFrame:frame];
	v.backgroundColor = [UIColor colorWithRed:0.96 green:0.78 blue:0.26 alpha:1.0];
	v.layer.cornerRadius = frame.size.height / 2;
	v.clipsToBounds = YES;

	UIBezierPath *person = [UIBezierPath bezierPath];
	CGFloat w = frame.size.width, h = frame.size.height;
	[person appendPath:[UIBezierPath bezierPathWithOvalInRect:
		CGRectMake(w * 0.34, h * 0.18, w * 0.32, h * 0.32)]];
	[person appendPath:[UIBezierPath bezierPathWithOvalInRect:
		CGRectMake(w * 0.20, h * 0.62, w * 0.60, h * 0.60)]];
	CAShapeLayer *pl = [CAShapeLayer layer];
	pl.path = person.CGPath;
	pl.fillColor = [UIColor whiteColor].CGColor;
	[v.layer addSublayer:pl];
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

		// 2) left fade strip
		UIImage *fadeImg = LoadLauncherImg(@"launcher_main_fade.webp");
		if (fadeImg) {
			UIImageView *fade = [[UIImageView alloc] initWithImage:fadeImg];
			fade.frame = CGRectMake(0, 0, W * 0.2812, H);
			fade.contentMode = UIViewContentModeScaleToFill;
			fade.autoresizingMask = UIViewAutoresizingFlexibleHeight;
			[launch addSubview:fade];
		}

		// 3) login fade top-right
		UIImage *loginFade = LoadLauncherImg(@"launcher_main_login_fade.webp");
		if (loginFade) {
			UIImageView *lf = [[UIImageView alloc] initWithImage:loginFade];
			lf.frame = CGRectMake(W - W * 0.2072, 0, W * 0.2072, H * 0.1648);
			lf.contentMode = UIViewContentModeScaleToFill;
			lf.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth;
			[launch addSubview:lf];
		}

		// 4) "ВЫБОР СЕРВЕРА" + swap button (dark rounded square)
		[launch addSubview:Label(CGRectMake(W * 0.02, H * 0.040, W * 0.14, H * 0.038),
			@"ВЫБОР СЕРВЕРА", H * 0.033, [UIColor whiteColor], YES, NO)];
		UIView *swapSq = PanelRect(CGRectMake(W * 0.165, H * 0.033, H * 0.055, H * 0.055),
			[UIColor colorWithWhite:0.05 alpha:0.55], H * 0.014, nil, 0);
		[swapSq addSubview:Label(swapSq.bounds, @"⇄", H * 0.032, [UIColor whiteColor], YES, YES)];
		[launch addSubview:swapSq];

		// 5) current server panel (name / red caption / progress + status)
		{
			CGFloat pw = W * 0.175, ph = H * 0.128;
			CGFloat px = W * 0.02, py = H * 0.094;
			[launch addSubview:PanelRect(CGRectMake(px, py, pw, ph),
				[UIColor colorWithWhite:0.0 alpha:0.28], H * 0.028,
				[UIColor colorWithWhite:1.0 alpha:0.25], 1.5)];

			// gold badge with "1"
			UIImage *goldImg = LoadLauncherImg(@"launcher_servers_item_gold_bg.webp");
			CGFloat bdW = W * 0.045;
			UIView *badge;
			if (goldImg) {
				badge = [[UIImageView alloc] initWithImage:goldImg];
				badge.frame = CGRectMake(px + W * 0.008, py + (ph - bdW) / 2, bdW, bdW);
				badge.contentMode = UIViewContentModeScaleToFill;
				badge.layer.cornerRadius = bdW * 0.22;
				badge.clipsToBounds = YES;
			} else {
				badge = PanelRect(CGRectMake(px + W * 0.008, py + (ph - bdW) / 2, bdW, bdW),
					[UIColor colorWithRed:0.97 green:0.80 blue:0.18 alpha:1.0], bdW * 0.22, nil, 0);
			}
			[badge addSubview:Label(badge.bounds, @"1", H * 0.055,
				[UIColor colorWithRed:0.29 green:0.23 blue:0.0 alpha:1.0], YES, YES)];
			[launch addSubview:badge];

			// texts right of the badge
			CGFloat tx = px + W * 0.008 + bdW + W * 0.012;
			CGFloat tw = px + pw - tx - W * 0.008;
			[launch addSubview:Label(CGRectMake(tx, py + ph * 0.10, tw, ph * 0.30),
				@"STAGE MOBILE", H * 0.028, [UIColor whiteColor], YES, NO)];
			[launch addSubview:Label(CGRectMake(tx, py + ph * 0.40, tw, ph * 0.22),
				@"ЗАГРУЖЕННОСТЬ СЕРВЕРА", H * 0.016,
				[UIColor colorWithRed:0.90 green:0.25 blue:0.22 alpha:1.0], YES, NO)];

			// progress bar + status at the right
			CGFloat pbW = tw * 0.42, pbH = H * 0.011;
			UIView *track = PanelRect(CGRectMake(tx, py + ph * 0.74, pbW, pbH),
				[UIColor colorWithWhite:1.0 alpha:0.30], pbH / 2, nil, 0);
			[track addSubview:PanelRect(CGRectMake(0, 0, pbW * 0.15, pbH),
				[UIColor colorWithWhite:1.0 alpha:0.95], pbH / 2, nil, 0)];
			[launch addSubview:track];
			[launch addSubview:Label(CGRectMake(tx + pbW + W * 0.008, py + ph * 0.66, tw - pbW - W * 0.008, ph * 0.26),
				@"ВЫСОКАЯ", H * 0.020, [UIColor whiteColor], YES, NO)];
		}

		// 6) account top-right (caption / nick / gold person badge)
		{
			CGFloat iconSz = H * 0.055, rightM = W * 0.012;
			[launch addSubview:AccountIcon(CGRectMake(W - iconSz - rightM, H * 0.030, iconSz, iconSz))];

			CGFloat aw = W * 0.20;
			UILabel *t = Label(CGRectMake(W - iconSz - rightM - W * 0.01 - aw, H * 0.022, aw, H * 0.028),
				@"ВАШ АККАУНТ", H * 0.021, [UIColor colorWithWhite:1.0 alpha:0.60], YES, YES);
			t.textAlignment = NSTextAlignmentRight;
			[launch addSubview:t];
			UILabel *n = Label(CGRectMake(W - iconSz - rightM - W * 0.01 - aw, H * 0.050, aw, H * 0.036),
				@"Denny_Walker", H * 0.030, [UIColor whiteColor], YES, YES);
			n.textAlignment = NSTextAlignmentRight;
			[launch addSubview:n];
		}

		// 7) АКЦИЯ X2 promo + pill (right side)
		{
			NSMutableAttributedString *promo = [[NSMutableAttributedString alloc]
				initWithString:@"АКЦИЯ X2"];
			[promo addAttribute:NSFontAttributeName
			          value:[UIFont systemFontOfSize:H * 0.047 weight:UIFontWeightHeavy]
			          range:NSMakeRange(0, 8)];
			[promo addAttribute:NSForegroundColorAttributeName value:[UIColor whiteColor] range:NSMakeRange(0, 5)];
			[promo addAttribute:NSForegroundColorAttributeName
			          value:[UIColor colorWithRed:0.68 green:0.88 blue:0.21 alpha:1.0]
			          range:NSMakeRange(6, 2)];
			UILabel *pl = [[UILabel alloc] initWithFrame:CGRectMake(W * 0.68, H * 0.175, W * 0.30, H * 0.062)];
			pl.attributedText = promo;
			pl.textAlignment = NSTextAlignmentRight;
			pl.adjustsFontSizeToFitWidth = YES;
			pl.minimumScaleFactor = 0.5;
			[launch addSubview:pl];

			UIView *pill = PanelRect(CGRectMake(W * 0.805, H * 0.258, W * 0.173, H * 0.048),
				[UIColor colorWithWhite:0.0 alpha:0.35], H * 0.024, nil, 0);
			[pill addSubview:Label(pill.bounds, @"ОПЫТ / ЗАРПЛАТЫ / ПОПОЛНЕНИЕ", H * 0.018,
				[UIColor whiteColor], YES, YES)];
			[launch addSubview:pill];
		}

		// 8) socials bottom-left (dark squares, white logos)
		{
			CGFloat sw = W * 0.045, gap = W * 0.0225, sy = H - sw - H * 0.055;
			[launch addSubview:YouTubeIcon(CGRectMake(W * 0.0225, sy, sw, sw))];
			[launch addSubview:VKIcon(CGRectMake(W * 0.0225 + sw + gap, sy, sw, sw))];
			[launch addSubview:TGIcon(CGRectMake(W * 0.0225 + (sw + gap) * 2, sy, sw, sw))];
		}

		// 9) PLAY button bottom-right
		{
			CGFloat bw = W * 0.20, bh = H * 0.145;
			CGFloat bx = W - bw - W * 0.0225, by = H - bh - H * 0.05;
			UIButton *play = [UIButton buttonWithType:UIButtonTypeCustom];
			play.frame = CGRectMake(bx, by, bw, bh);

			CAGradientLayer *grad = [CAGradientLayer layer];
			grad.frame = play.bounds;
			grad.colors = @[
				(id)[UIColor colorWithRed:0xd1/255.0 green:0xff/255.0 blue:0x6f/255.0 alpha:1.0].CGColor,
				(id)[UIColor colorWithRed:0x76/255.0 green:0xf8/255.0 blue:0x10/255.0 alpha:1.0].CGColor ];
			grad.startPoint = CGPointMake(0.5, 0.0);
			grad.endPoint = CGPointMake(0.5, 1.0);
			grad.cornerRadius = H * 0.033;
			grad.masksToBounds = YES;
			[play.layer insertSublayer:grad atIndex:0];

			[play setTitle:@"ИГРАТЬ" forState:UIControlStateNormal];
			[play setTitleColor:[UIColor colorWithRed:0x2e/255.0 green:0x52/255.0 blue:0x14/255.0 alpha:1.0]
			               forState:UIControlStateNormal];
			play.titleLabel.font = [UIFont systemFontOfSize:H * 0.061 weight:UIFontWeightHeavy];
			play.titleLabel.adjustsFontSizeToFitWidth = YES;
			play.titleLabel.minimumScaleFactor = 0.5;
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
