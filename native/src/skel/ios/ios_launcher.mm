#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static volatile int g_playPressed = 0;

// ---------------------------------------------------------------- server data
typedef struct {
	CGFloat load;      // 0..1
	const char *status;
} ServerInfo;

static ServerInfo g_servers[] = {
	{ 0.30, "ВЫСОКАЯ" },
	{ 0.55, "СРЕДНЯЯ" },
	{ 0.15, "НИЗКАЯ" },
	{ 0.70, "ВЫСОКАЯ" },
	{ 0.42, "СРЕДНЯЯ" },
	{ 0.85, "ВЫСОКАЯ" },
};
static const int g_serverCount = sizeof(g_servers) / sizeof(g_servers[0]);
static NSInteger g_selectedServer = 0;

// live refs to main-screen labels so selection can update them
static UILabel *g_mainBadgeNum;
static UILabel *g_mainStatus;
static UIView *g_mainProgressFill;
static CGFloat g_mainTrackW, g_mainTrackH;

static const NSInteger kTagMain = 777001;
static const NSInteger kTagLoader = 777002;
static const NSInteger kTagServers = 777003;

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

// ------------------------------------------------------------- press effects
@interface REVCPressHelper : NSObject
@property (nonatomic, copy) void (^onTap)(void);
@end

@implementation REVCPressHelper
- (void)handlePress:(UILongPressGestureRecognizer *)g
{
	UIView *v = g.view;
	if (g.state == UIGestureRecognizerStateBegan) {
		[UIView animateWithDuration:0.12
		                      delay:0
		                    options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
		                 animations:^{ v.transform = CGAffineTransformMakeScale(0.92, 0.92); }
		                 completion:nil];
	} else if (g.state == UIGestureRecognizerStateEnded) {
		[UIView animateWithDuration:0.55
		                      delay:0
		 usingSpringWithDamping:0.5
		  initialSpringVelocity:8.0
		                    options:UIViewAnimationOptionBeginFromCurrentState
		                 animations:^{ v.transform = CGAffineTransformIdentity; }
		                 completion:nil];
		if (self.onTap) {
			void (^tap)(void) = self.onTap;
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)),
			    dispatch_get_main_queue(), tap);
		}
	} else if (g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) {
		[UIView animateWithDuration:0.35
		                      delay:0
		 usingSpringWithDamping:0.6
		  initialSpringVelocity:6.0
		                    options:UIViewAnimationOptionBeginFromCurrentState
		                 animations:^{ v.transform = CGAffineTransformIdentity; }
		                 completion:nil];
	}
}
@end

static void
MakePressable(UIView *v, void (^onTap)(void))
{
	static char kHelperKey;
	REVCPressHelper *h = [REVCPressHelper new];
	h.onTap = onTap;
	UILongPressGestureRecognizer *g =
	    [[UILongPressGestureRecognizer alloc] initWithTarget:h action:@selector(handlePress:)];
	g.minimumPressDuration = 0.05;
	g.cancelsTouchesInView = NO;
	[v addGestureRecognizer:g];
	objc_setAssociatedObject(v, &kHelperKey, h, OBJC_ASSOCIATION_RETAIN);
}

// ------------------------------------------------------------------ helpers
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

static UIImageView *
BgView(CGRect frame, NSString *asset, UIViewContentMode mode)
{
	UIImageView *iv = [[UIImageView alloc] initWithImage:LoadLauncherImg(asset)];
	iv.frame = frame;
	iv.contentMode = mode;
	iv.clipsToBounds = YES;
	iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	return iv;
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
	return l;
}

static UIView *
DarkSquare(CGRect frame, CGFloat radius)
{
	return PanelRect(frame, [UIColor colorWithWhite:0.05 alpha:0.55], radius, nil, 0);
}

// YouTube: white rounded-rect play glyph on a dark translucent square
static UIView *
YouTubeIcon(CGRect frame)
{
	UIView *v = DarkSquare(frame, frame.size.height * 0.24);

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
	UIView *v = DarkSquare(frame, frame.size.height * 0.24);
	[v addSubview:Label(v.bounds, @"VK", frame.size.height * 0.36, [UIColor whiteColor], YES, YES)];
	return v;
}

// Telegram: white paper plane on a dark translucent square
static UIView *
TGIcon(CGRect frame)
{
	UIView *v = DarkSquare(frame, frame.size.height * 0.24);

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

// one server list item, per launcher_servers_item.xml
static UIView *
ServerItem(CGSize size, NSInteger idx, void (^onSelect)(NSInteger))
{
	CGFloat iw = size.width, ih = size.height;
	UIView *item = PanelRect(CGRectMake(0, 0, iw, ih),
		[UIColor colorWithWhite:0.0 alpha:0.18], iw * 0.060,
		[UIColor colorWithWhite:1.0 alpha:0.22], MAX(1.0, iw * 0.007));

	// gold badge with #N
	UIImage *goldImg = LoadLauncherImg(@"launcher_servers_item_gold_bg.webp");
	CGFloat bw = ih * 0.766;
	UIView *badge;
	if (goldImg) {
		badge = [[UIImageView alloc] initWithImage:goldImg];
		badge.frame = CGRectMake(0.06 * (iw - bw), (ih - bw) / 2, bw, bw);
		badge.contentMode = UIViewContentModeScaleToFill;
		badge.layer.cornerRadius = bw * 0.22;
		badge.clipsToBounds = YES;
	} else {
		badge = PanelRect(CGRectMake(0.06 * (iw - bw), (ih - bw) / 2, bw, bw),
			[UIColor colorWithRed:0.97 green:0.80 blue:0.18 alpha:1.0], bw * 0.22, nil, 0);
	}
	[badge addSubview:Label(badge.bounds,
		[NSString stringWithFormat:@"#%ld", (long)(idx + 1)], bw * 0.46,
		[UIColor colorWithRed:0x4d/255.0 green:0x37/255.0 blue:0x09/255.0 alpha:1.0], YES, YES)];
	[item addSubview:badge];

	// name
	CGFloat nx = iw * 0.367, nw = iw * 0.46;
	[item addSubview:Label(CGRectMake(nx, ih * 0.16, nw, ih * 0.24),
		@"LIT MOBILE", iw * 0.081, [UIColor whiteColor], YES, NO)];

	// caption
	[item addSubview:Label(CGRectMake(nx, ih * 0.42, nw, ih * 0.15),
		@"ЗАГРУЖЕННОСТЬ СЕРВЕРА", iw * 0.0405,
		[UIColor colorWithWhite:1.0 alpha:0.50], YES, NO)];

	// progress + status
	CGFloat pw = iw * 0.2857, ph = ih * 0.062;
	CGFloat px = 0.51 * (iw - pw), py = ih * 0.78;
	UIView *track = PanelRect(CGRectMake(px, py, pw, ph),
		[UIColor colorWithWhite:1.0 alpha:0.30], ph / 2, nil, 0);
	UIView *fill = PanelRect(CGRectMake(0, 0, pw * g_servers[idx].load, ph),
		[UIColor colorWithRed:0.68 green:0.88 blue:0.21 alpha:1.0], ph / 2, nil, 0);
	[track addSubview:fill];
	[item addSubview:track];
	[item addSubview:Label(CGRectMake(iw * 0.70, py - ih * 0.03, iw * 0.26, ph + ih * 0.06),
		@(g_servers[idx].status), iw * 0.061, [UIColor whiteColor], YES, YES)];

	// character-exists + recommended icons on the first server
	if (idx == 0) {
		UIImageView *ch = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_servers_item_char_ic.webp")];
		CGFloat cw = ih * 0.2765;
		ch.frame = CGRectMake(0.955 * (iw - cw), 0.14 * (ih - cw), cw, cw);
		ch.contentMode = UIViewContentModeScaleAspectFit;
		[item addSubview:ch];

		UIImageView *rec = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_servers_item_recommended_ic.webp")];
		CGFloat rw = ih * 0.18;
		rec.frame = CGRectMake((iw - rw) / 2, (ih - rw) / 2, rw, rw);
		rec.contentMode = UIViewContentModeScaleAspectFit;
		[item addSubview:rec];
	}

	MakePressable(item, ^{
		if (onSelect)
			onSelect(idx);
	});
	return item;
}

// ------------------------------------------------------------ servers screen
static void
HideServers(UIView *root);

static void
ShowServers(UIView *root)
{
	if ([root viewWithTag:kTagServers])
		return;

	CGRect b = root.bounds;
	CGFloat W = b.size.width, H = b.size.height;

	UIView *scr = [[UIView alloc] initWithFrame:b];
	scr.tag = kTagServers;
	scr.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	scr.backgroundColor = [UIColor blackColor];
	scr.transform = CGAffineTransformMakeTranslation(W, 0);
	scr.alpha = 0.6;

	// bg art + dark blur overlay (#99000000 like the XML)
	[scr addSubview:BgView(b, @"launcher_main_bg.webp", UIViewContentModeScaleAspectFill)];
	[scr addSubview:PanelRect(b, [UIColor colorWithRed:0 green:0 blue:0 alpha:0.60], 0, nil, 0)];

	// back button
	UIImageView *back = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_servers_back_btn.webp")];
	CGFloat bh2 = H * 0.125;
	CGFloat bw2 = bh2 * (back.image ? back.image.size.width / back.image.size.height : 1.4);
	back.frame = CGRectMake(0.011 * (W - bw2), 0.028 * (H - bh2), bw2, bh2);
	back.contentMode = UIViewContentModeScaleAspectFit;
	[scr addSubview:back];

	// centered title
	[scr addSubview:Label(CGRectMake(W * 0.30, H * 0.030, W * 0.40, H * 0.042),
		@"ВЫБОР СЕРВЕРА", H * 0.033, [UIColor whiteColor], YES, YES)];

	// favourites row
	[scr addSubview:Label(CGRectMake(W * 0.051, H * 0.165, W * 0.30, H * 0.034),
		@"Избранные сервера:", H * 0.024, [UIColor whiteColor], YES, NO)];

	CGFloat iw = W * 0.30, ih = iw / 2.9;
	UIScrollView *favRow = [[UIScrollView alloc] initWithFrame:CGRectMake(W * 0.051, H * 0.215, W * 0.879, ih)];
	favRow.showsHorizontalScrollIndicator = NO;
	favRow.alwaysBounceHorizontal = YES;
	for (int i = 0; i < 3 && i < g_serverCount; i++) {
		UIView *it = ServerItem(CGSizeMake(iw, ih), i, ^(NSInteger sel) {
			g_selectedServer = sel;
			if (g_mainBadgeNum)
				g_mainBadgeNum.text = [NSString stringWithFormat:@"%ld", (long)(sel + 1)];
			if (g_mainStatus)
				g_mainStatus.text = @(g_servers[sel].status);
			if (g_mainProgressFill)
				g_mainProgressFill.frame = CGRectMake(0, 0, g_mainTrackW * g_servers[sel].load, g_mainTrackH);
			HideServers(root);
		});
		it.frame = CGRectMake(i * (iw + W * 0.02), 0, iw, ih);
		[favRow addSubview:it];
	}
	favRow.contentSize = CGSizeMake(3 * iw + 2 * W * 0.02, ih);
	[scr addSubview:favRow];

	// all servers grid
	[scr addSubview:Label(CGRectMake(W * 0.051, H * 0.470, W * 0.30, H * 0.034),
		@"Все сервера:", H * 0.024, [UIColor whiteColor], YES, NO)];

	UIScrollView *grid = [[UIScrollView alloc] initWithFrame:CGRectMake(W * 0.051, H * 0.520, W * 0.879, H * 0.40)];
	grid.showsVerticalScrollIndicator = NO;
	grid.alwaysBounceVertical = YES;
	CGFloat cols = 3, gapX = (W * 0.879 - 3 * iw) / 2, gapY = H * 0.025;
	for (int i = 0; i < g_serverCount; i++) {
		int row = i / (int)cols, col = i % (int)cols;
		UIView *it = ServerItem(CGSizeMake(iw, ih), i, ^(NSInteger sel) {
			g_selectedServer = sel;
			if (g_mainBadgeNum)
				g_mainBadgeNum.text = [NSString stringWithFormat:@"%ld", (long)(sel + 1)];
			if (g_mainStatus)
				g_mainStatus.text = @(g_servers[sel].status);
			if (g_mainProgressFill)
				g_mainProgressFill.frame = CGRectMake(0, 0, g_mainTrackW * g_servers[sel].load, g_mainTrackH);
			HideServers(root);
		});
		it.frame = CGRectMake(col * (iw + gapX), row * (ih + gapY), iw, ih);
		[grid addSubview:it];
	}
	int rows = (g_serverCount + 2) / 3;
	grid.contentSize = CGSizeMake(W * 0.879, rows * ih + (rows - 1) * gapY);
	[scr addSubview:grid];

	// bottom icons near the center line
	CGFloat icH = H * 0.0925;
	UIImageView *recIc = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_servers_recommended_ic.webp")];
	recIc.frame = CGRectMake(W * 0.4471 - icH - W * 0.008, H - icH - H * 0.02, icH, icH);
	recIc.contentMode = UIViewContentModeScaleAspectFit;
	[scr addSubview:recIc];
	UIImageView *charsIc = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_servers_created_chars_ic.webp")];
	charsIc.frame = CGRectMake(W * 0.4471 + W * 0.008, H - icH - H * 0.02, icH, icH);
	charsIc.contentMode = UIViewContentModeScaleAspectFit;
	[scr addSubview:charsIc];

	MakePressable(back, ^{
		HideServers(root);
	});

	[root addSubview:scr];

	// slide in from the right with a spring
	[UIView animateWithDuration:0.5
	                      delay:0
	 usingSpringWithDamping:0.85
	  initialSpringVelocity:4.0
	                    options:UIViewAnimationOptionCurveEaseOut
	                 animations:^{ scr.transform = CGAffineTransformIdentity; scr.alpha = 1.0; }
	                 completion:nil];
}

static void
HideServers(UIView *root)
{
	UIView *scr = [root viewWithTag:kTagServers];
	if (!scr)
		return;
	[UIView animateWithDuration:0.4
	                      delay:0
	                    options:UIViewAnimationOptionCurveEaseIn
	                 animations:^{ scr.transform = CGAffineTransformMakeTranslation(root.bounds.size.width, 0); scr.alpha = 0.3; }
	                 completion:^(BOOL finished) { [scr removeFromSuperview]; }];
}

// ---------------------------------------------------------- loader (startup)
static void
ShowLoader(UIView *root)
{
	CGRect b = root.bounds;
	CGFloat W = b.size.width, H = b.size.height;

	UIView *ldr = [[UIView alloc] initWithFrame:b];
	ldr.tag = kTagLoader;
	ldr.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	ldr.backgroundColor = [UIColor blackColor];

	[ldr addSubview:BgView(b, @"launcher_loader_bg.webp", UIViewContentModeScaleAspectFill)];
	[ldr addSubview:PanelRect(b, [UIColor colorWithRed:0 green:0 blue:0 alpha:0.60], 0, nil, 0)];

	// spinning ring (stands in for the lottie loader_screen_progress)
	CGFloat d = H * 0.07;
	UIView *spinner = [[UIView alloc] initWithFrame:CGRectMake((W - d) / 2, 0.45 * (H - d), d, d)];

	UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:CGPointMake(d / 2, d / 2)
	                                                 radius:d * 0.40
	                                             startAngle:-M_PI / 2
	                                               endAngle:-M_PI / 2 + M_PI * 1.4
	                                              clockwise:YES];
	CAShapeLayer *ring = [CAShapeLayer layer];
	ring.path = p.CGPath;
	ring.fillColor = nil;
	ring.strokeColor = [UIColor whiteColor].CGColor;
	ring.lineWidth = d * 0.09;
	ring.lineCap = kCALineCapRound;
	[spinner.layer addSublayer:ring];

	CABasicAnimation *rot = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
	rot.fromValue = @0.0;
	rot.toValue = @(2 * M_PI);
	rot.duration = 0.9;
	rot.repeatCount = HUGE_VALF;
	[ring addAnimation:rot forKey:@"spin"];
	[ldr addSubview:spinner];

	[ldr addSubview:Label(CGRectMake(W * 0.25, spinner.frame.origin.y + d + H * 0.016,
		W * 0.50, H * 0.034), @"ОЖИДАНИЕ ЗАГРУЗКИ", H * 0.026, [UIColor whiteColor], YES, YES)];

	[root addSubview:ldr];

	// hold the loader a moment, then reveal the main screen
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		UIView *l = [root viewWithTag:kTagLoader];
		if (!l)
			return;
		[UIView animateWithDuration:0.5
		                      delay:0
		                    options:UIViewAnimationOptionCurveEaseInOut
		                 animations:^{ l.alpha = 0.0; }
		                 completion:^(BOOL finished) { [l removeFromSuperview]; }];
	});
}

// ---------------------------------------------------------------- main screen
static void
BuildMainScreen(UIView *root)
{
	CGRect b = root.bounds;
	CGFloat W = b.size.width, H = b.size.height;

	UIView *launch = [[UIView alloc] initWithFrame:b];
	launch.tag = kTagMain;
	launch.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	launch.backgroundColor = [UIColor blackColor];

	[launch addSubview:BgView(b, @"launcher_main_bg.webp", UIViewContentModeScaleAspectFill)];

	UIImage *fadeImg = LoadLauncherImg(@"launcher_main_fade.webp");
	if (fadeImg) {
		UIImageView *fade = [[UIImageView alloc] initWithImage:fadeImg];
		fade.frame = CGRectMake(0, 0, W * 0.2812, H);
		fade.contentMode = UIViewContentModeScaleToFill;
		fade.autoresizingMask = UIViewAutoresizingFlexibleHeight;
		[launch addSubview:fade];
	}

	UIImage *loginFade = LoadLauncherImg(@"launcher_main_login_fade.webp");
	if (loginFade) {
		UIImageView *lf = [[UIImageView alloc] initWithImage:loginFade];
		lf.frame = CGRectMake(W - W * 0.2072, 0, W * 0.2072, H * 0.1648);
		lf.contentMode = UIViewContentModeScaleToFill;
		lf.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth;
		[launch addSubview:lf];
	}

	// "ВЫБОР СЕРВЕРА" + swap button -> opens the servers list
	[launch addSubview:Label(CGRectMake(W * 0.02, H * 0.040, W * 0.14, H * 0.038),
		@"ВЫБОР СЕРВЕРА", H * 0.033, [UIColor whiteColor], YES, NO)];
	UIView *swapSq = DarkSquare(CGRectMake(W * 0.165, H * 0.033, H * 0.055, H * 0.055), H * 0.014);
	[swapSq addSubview:Label(swapSq.bounds, @"⇄", H * 0.032, [UIColor whiteColor], YES, YES)];
	[launch addSubview:swapSq];

	// current server panel (tap -> servers list)
	{
		CGFloat pw = W * 0.175, ph = H * 0.128;
		CGFloat px = W * 0.02, py = H * 0.094;
		UIView *panel = PanelRect(CGRectMake(px, py, pw, ph),
			[UIColor colorWithWhite:0.0 alpha:0.28], H * 0.028,
			[UIColor colorWithWhite:1.0 alpha:0.25], 1.5);

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
		g_mainBadgeNum = Label(badge.bounds,
			[NSString stringWithFormat:@"%ld", (long)(g_selectedServer + 1)], H * 0.055,
			[UIColor colorWithRed:0x4d/255.0 green:0x37/255.0 blue:0x09/255.0 alpha:1.0], YES, YES);
		[badge addSubview:g_mainBadgeNum];
		[launch addSubview:badge];

		CGFloat tx = px + W * 0.008 + bdW + W * 0.012;
		CGFloat tw = px + pw - tx - W * 0.008;
		[launch addSubview:Label(CGRectMake(tx, py + ph * 0.10, tw, ph * 0.30),
			@"LIT MOBILE", H * 0.028, [UIColor whiteColor], YES, NO)];
		[launch addSubview:Label(CGRectMake(tx, py + ph * 0.40, tw, ph * 0.22),
			@"ЗАГРУЖЕННОСТЬ СЕРВЕРА", H * 0.016,
			[UIColor colorWithRed:0.90 green:0.25 blue:0.22 alpha:1.0], YES, NO)];

		CGFloat pbW = tw * 0.42, pbH = H * 0.011;
		g_mainTrackW = pbW;
		g_mainTrackH = pbH;
		UIView *track = PanelRect(CGRectMake(tx, py + ph * 0.74, pbW, pbH),
			[UIColor colorWithWhite:1.0 alpha:0.30], pbH / 2, nil, 0);
		g_mainProgressFill = PanelRect(CGRectMake(0, 0, pbW * g_servers[g_selectedServer].load, pbH),
			[UIColor colorWithWhite:1.0 alpha:0.95], pbH / 2, nil, 0);
		[track addSubview:g_mainProgressFill];
		[launch addSubview:track];
		g_mainStatus = Label(CGRectMake(tx + pbW + W * 0.008, py + ph * 0.66, tw - pbW - W * 0.008, ph * 0.26),
			@(g_servers[g_selectedServer].status), H * 0.020, [UIColor whiteColor], YES, NO);
		[launch addSubview:g_mainStatus];

		MakePressable(panel, ^{ ShowServers(root); });
	}
	MakePressable(swapSq, ^{ ShowServers(root); });

	// account top-right
	{
		CGFloat iconSz = H * 0.055, rightM = W * 0.012;
		[launch addSubview:AccountIcon(CGRectMake(W - iconSz - rightM, H * 0.030, iconSz, iconSz))];

		CGFloat aw = W * 0.20;
		UILabel *t = Label(CGRectMake(W - iconSz - rightM - W * 0.01 - aw, H * 0.022, aw, H * 0.028),
			@"ВАШ АККАУНТ", H * 0.021, [UIColor colorWithWhite:1.0 alpha:0.60], YES, YES);
		t.textAlignment = NSTextAlignmentRight;
		[launch addSubview:t];
		UILabel *n = Label(CGRectMake(W - iconSz - rightM - W * 0.01 - aw, H * 0.050, aw, H * 0.036),
			@"Logountw", H * 0.030, [UIColor whiteColor], YES, YES);
		n.textAlignment = NSTextAlignmentRight;
		[launch addSubview:n];
	}

	// АКЦИЯ X2 promo + pill
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

	// socials bottom-left
	{
		CGFloat sw = W * 0.045, gap = W * 0.0225, sy = H - sw - H * 0.055;
		UIView *yt = YouTubeIcon(CGRectMake(W * 0.0225, sy, sw, sw));
		UIView *vk = VKIcon(CGRectMake(W * 0.0225 + sw + gap, sy, sw, sw));
		UIView *tg = TGIcon(CGRectMake(W * 0.0225 + (sw + gap) * 2, sy, sw, sw));
		MakePressable(yt, nil);
		MakePressable(vk, nil);
		MakePressable(tg, nil);
		[launch addSubview:yt];
		[launch addSubview:vk];
		[launch addSubview:tg];
	}

	// PLAY button bottom-right
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
		MakePressable(play, ^{ [[REVCLauncherTap shared] playTapped]; });
		[launch addSubview:play];
	}

	[root addSubview:launch];
	[root bringSubviewToFront:launch];
}

// ------------------------------------------------------------------- public
extern "C" void
ios_show_launcher(void *uiwindow)
{
	@autoreleasepool {
		UIWindow *uiw = (__bridge UIWindow *)uiwindow;
		UIView *root = uiw.rootViewController.view;
		if (!root)
			return;
		[root layoutIfNeeded];

		g_playPressed = 0;
		g_mainBadgeNum = nil;
		g_mainStatus = nil;
		g_mainProgressFill = nil;

		BuildMainScreen(root);
		ShowLoader(root);
	}
}

extern "C" int
ios_play_pressed(void)
{
	// remove the launcher the moment play was pressed (caller resumes the game)
	if (g_playPressed) {
		dispatch_async(dispatch_get_main_queue(), ^{
			NSArray<NSNumber *> *tags = @[ @(kTagMain), @(kTagLoader), @(kTagServers) ];
			for (UIWindow *w in [UIApplication sharedApplication].windows) {
				for (NSNumber *t in tags) {
					UIView *v = [w viewWithTag:t.integerValue];
					if (v)
						[v removeFromSuperview];
				}
			}
		});
		return 1;
	}
	return 0;
}
