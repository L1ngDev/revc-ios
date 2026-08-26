#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <stdlib.h>

static volatile int g_playPressed = 0;

// ---------------------------------------------------------------- server data
typedef struct {
	CGFloat load;        // 0..1 progress
	const char *sub;     // red subtitle
} ServerInfo;

static ServerInfo g_servers[] = {
	{ 0.01, "ОСНОВНОЙ" },
	{ 0.01, "ТЕСТОВЫЙ, ДОСТУП ПО ПРИГЛАШЕНИЮ" },
};
static const int g_serverCount = sizeof(g_servers) / sizeof(g_servers[0]);
static NSInteger g_selectedServer = 0;

// main-screen server panel (a real launcher_servers_item), rebuilt on selection
static UIView *g_mainPanelHolder;

static const NSInteger kTagMain = 777001;
static const NSInteger kTagLoader = 777002;
static const NSInteger kTagServers = 777003;

static NSString *
ServerName(NSInteger idx)
{
	return [NSString stringWithFormat:@"LIT MOBILE #%ld", (long)(idx + 1)];
}

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

// smooth system blur overlay (goes on top of the bg art)
static UIView *
SmoothBlurOverlay(CGRect frame)
{
	UIVisualEffectView *v = [[UIVisualEffectView alloc]
		initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
	v.frame = frame;
	v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	return v;
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

// ------------------------------------------------- SVG path -> UIBezierPath
// Minimal SVG path parser (Android vector pathData): M L H V C S Q T A Z, abs+rel.
// Arc rotation is assumed 0 (all NORMSOURCE icons use circular arcs).
static void
SvgPathToBezier(NSString *d, CGFloat sc, UIBezierPath *p)
{
	if (!d)
		return;
	const char *s = [d UTF8String];
	char cmd = 0;
	CGFloat cx = 0, cy = 0, sx = 0, sy = 0;
	CGFloat lc2x = 0, lc2y = 0, lqx = 0, lqy = 0;
	BOOL hadC = NO, hadQ = NO;

#define NEXT_NUM(var) do { char *e; (var) = (CGFloat)strtod(s, &e); if (e == s) return; s = e; while (*s == ' ' || *s == ',') s++; } while (0)

	while (*s) {
		while (*s == ' ' || *s == ',' || *s == '\n' || *s == '\r' || *s == '\t')
			s++;
		if (!*s)
			break;
		if ((*s >= 'A' && *s <= 'Z') || (*s >= 'a' && *s <= 'z')) {
			cmd = *s++;
			continue;
		}
		CGFloat a = 0, b = 0, c = 0, e2 = 0, f = 0, g = 0, h = 0;
		switch (cmd) {
		case 'M': case 'm': {
			NEXT_NUM(a); NEXT_NUM(b);
			if (cmd == 'm') { a += cx; b += cy; }
			[p moveToPoint:CGPointMake(a * sc, b * sc)];
			cx = sx = a; cy = sy = b;
			cmd = (cmd == 'm') ? 'l' : 'L';
			hadC = hadQ = NO;
			break; }
		case 'L': case 'l': {
			NEXT_NUM(a); NEXT_NUM(b);
			if (cmd == 'l') { a += cx; b += cy; }
			[p addLineToPoint:CGPointMake(a * sc, b * sc)];
			cx = a; cy = b; hadC = hadQ = NO;
			break; }
		case 'H': case 'h': {
			NEXT_NUM(a);
			if (cmd == 'h') a += cx;
			[p addLineToPoint:CGPointMake(a * sc, cy * sc)];
			cx = a; hadC = hadQ = NO;
			break; }
		case 'V': case 'v': {
			NEXT_NUM(b);
			if (cmd == 'v') b += cy;
			[p addLineToPoint:CGPointMake(cx * sc, b * sc)];
			cy = b; hadC = hadQ = NO;
			break; }
		case 'C': case 'c': {
			NEXT_NUM(a); NEXT_NUM(b); NEXT_NUM(c); NEXT_NUM(e2); NEXT_NUM(f); NEXT_NUM(g);
			if (cmd == 'c') { a += cx; b += cy; c += cx; e2 += cy; f += cx; g += cy; }
			[p addCurveToPoint:CGPointMake(f * sc, g * sc)
			              controlPoint1:CGPointMake(a * sc, b * sc)
			              controlPoint2:CGPointMake(c * sc, e2 * sc)];
			lc2x = c; lc2y = e2; cx = f; cy = g; hadC = YES; hadQ = NO;
			break; }
		case 'S': case 's': {
			NEXT_NUM(c); NEXT_NUM(e2); NEXT_NUM(f); NEXT_NUM(g);
			if (cmd == 's') { c += cx; e2 += cy; f += cx; g += cy; }
			a = hadC ? 2 * cx - lc2x : cx;
			b = hadC ? 2 * cy - lc2y : cy;
			[p addCurveToPoint:CGPointMake(f * sc, g * sc)
			              controlPoint1:CGPointMake(a * sc, b * sc)
			              controlPoint2:CGPointMake(c * sc, e2 * sc)];
			lc2x = c; lc2y = e2; cx = f; cy = g; hadC = YES; hadQ = NO;
			break; }
		case 'Q': case 'q': {
			NEXT_NUM(a); NEXT_NUM(b); NEXT_NUM(f); NEXT_NUM(g);
			if (cmd == 'q') { a += cx; b += cy; f += cx; g += cy; }
			[p addQuadCurveToPoint:CGPointMake(f * sc, g * sc)
			                controlPoint:CGPointMake(a * sc, b * sc)];
			lqx = a; lqy = b; cx = f; cy = g; hadQ = YES; hadC = NO;
			break; }
		case 'T': case 't': {
			NEXT_NUM(f); NEXT_NUM(g);
			if (cmd == 't') { f += cx; g += cy; }
			a = hadQ ? 2 * cx - lqx : cx;
			b = hadQ ? 2 * cy - lqy : cy;
			[p addQuadCurveToPoint:CGPointMake(f * sc, g * sc)
			                controlPoint:CGPointMake(a * sc, b * sc)];
			lqx = a; lqy = b; cx = f; cy = g; hadQ = YES; hadC = NO;
			break; }
		case 'A': case 'a': {
			NEXT_NUM(a); NEXT_NUM(b); NEXT_NUM(c); NEXT_NUM(e2); NEXT_NUM(f); NEXT_NUM(g); NEXT_NUM(h);
			CGFloat x2 = (cmd == 'a') ? cx + g : g;
			CGFloat y2 = (cmd == 'a') ? cy + h : h;
			CGFloat rx = fabs(a) * sc, ry = fabs(b) * sc;
			CGFloat x1 = cx * sc, y1 = cy * sc;
			x2 *= sc; y2 *= sc;
			if (rx <= 0.0001 || ry <= 0.0001) {
				[p addLineToPoint:CGPointMake(x2, y2)];
			} else {
				CGFloat x1p = (x1 - x2) / 2, y1p = (y1 - y2) / 2;
				CGFloat lam = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry);
				if (lam > 1) {
					CGFloat sq = sqrt(lam);
					rx *= sq; ry *= sq;
				}
				CGFloat sgn = (e2 != f) ? 1.0 : -1.0;
				CGFloat num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
				CGFloat den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
				CGFloat co = (fabs(den) < 1e-9) ? 0 : sgn * sqrt(MAX(0.0, num / den));
				CGFloat cxp = co * rx * y1p / ry;
				CGFloat cyp = -co * ry * x1p / rx;
				CGFloat ccx = cxp + (x1 + x2) / 2;
				CGFloat ccy = cyp + (y1 + y2) / 2;
				CGFloat ux = (x1p - cxp) / rx;
				CGFloat uy = (y1p - cyp) / ry;
				CGFloat vx = (-x1p - cxp) / rx;
				CGFloat vy = (-y1p - cyp) / ry;
				CGFloat t1 = atan2(uy, ux);
				CGFloat t2 = atan2(vy, vx);
				CGFloat dt = t2 - t1;
				if (!f && dt > 0) dt -= 2 * M_PI;
				if (f && dt < 0) dt += 2 * M_PI;
				[p addArcWithCenter:CGPointMake(ccx, ccy)
				             radius:rx
				         startAngle:t1
				           endAngle:t1 + dt
				          clockwise:(f != 0)];
			}
			cx = x2 / sc; cy = y2 / sc;
			hadC = hadQ = NO;
			break; }
		case 'Z': case 'z': {
			[p closePath];
			cx = sx; cy = sy;
			hadC = hadQ = NO;
			break; }
		default:
			NEXT_NUM(a);
			break;
		}
	}
#undef NEXT_NUM
}

// gradient-filled vector path (Android <gradient> fillers)
static CAGradientLayer *
GradientPathLayer(NSString *d, CGSize size, CGPoint g0, CGPoint g1,
    UIColor *c0, UIColor *c1, CGFloat opacity)
{
	UIBezierPath *p = [UIBezierPath bezierPath];
	SvgPathToBezier(d, size.width / 114.0, p);
	CAGradientLayer *g = [CAGradientLayer layer];
	g.frame = CGRectMake(0, 0, size.width, size.height);
	g.colors = @[ (id)c0.CGColor, (id)c1.CGColor ];
	g.startPoint = g0;
	g.endPoint = g1;
	g.opacity = opacity;
	CAShapeLayer *mask = [CAShapeLayer layer];
	mask.path = p.CGPath;
	mask.fillRule = kCAFillRuleEvenOdd;
	g.mask = mask;
	return g;
}

// exact vector art from launcher_main_{yt,vk,tg}_social.xml
static NSString *const kSocialSquarePath =
	@"M26.72,0L87.28,0A26.72,26.72 0,0 1,114 26.72L114,87.28A26.72,26.72 0,0 1,87.28 114L26.72,114A26.72,26.72 0,0 1,0 87.28L0,26.72A26.72,26.72 0,0 1,26.72 0z";
static NSString *const kYtGlyphPath =
	@"M92.48,27.38C96.18,28.36 99.11,31.24 100.11,34.89C101.96,41.55 101.89,55.44 101.89,55.44C101.89,55.44 101.89,69.26 100.11,75.93C99.11,79.58 96.18,82.45 92.48,83.43C85.7,85.19 58.61,85.19 58.61,85.19C58.61,85.19 31.58,85.19 24.74,83.36C21.03,82.38 18.11,79.51 17.11,75.86C15.32,69.26 15.32,55.37 15.32,55.37C15.32,55.37 15.32,41.55 17.11,34.89C18.1,31.24 21.1,28.29 24.74,27.31C31.51,25.56 58.61,25.56 58.61,25.56C58.61,25.56 85.7,25.56 92.48,27.38ZM72.51,55.37L49.98,68.14V42.6L72.51,55.37Z";
static NSString *const kVkGlyphPath =
	@"M24.61,24.97C19.34,30.3 19.34,38.81 19.34,55.86V58.88C19.34,75.9 19.34,84.42 24.61,89.77C29.94,95.04 38.45,95.04 55.5,95.04H58.52C75.54,95.04 84.06,95.04 89.41,89.77C94.68,84.44 94.68,75.93 94.68,58.88V55.86C94.68,38.84 94.68,30.32 89.41,24.97C84.08,19.7 75.57,19.7 58.52,19.7H55.5C38.48,19.7 29.96,19.7 24.61,24.97ZM32.73,43.16C33.13,63.03 42.91,74.95 60.07,74.95H60.1H61.08V63.59C67.38,64.23 72.14,68.91 74.05,74.95H82.96C82.04,71.52 80.42,68.33 78.2,65.58C75.99,62.83 73.22,60.59 70.09,59.01C72.89,57.27 75.32,54.97 77.21,52.24C79.1,49.51 80.42,46.41 81.07,43.14H73C71.24,49.46 66.02,55.19 61.08,55.72V43.16H52.97V65.17C47.96,63.9 41.63,57.73 41.36,43.16H32.73Z";
static NSString *const kTgGlyphPath =
	@"M34.66,19.7C25.99,19.7 18.96,26.73 18.96,35.4V79.34C18.96,88.01 25.99,95.04 34.66,95.04H78.61C87.28,95.04 94.31,88.01 94.31,79.34V35.4C94.31,26.73 87.28,19.7 78.61,19.7H34.66ZM82.68,36.37L73.83,78.95C73.62,79.95 72.44,80.41 71.61,79.8L59.53,71.03C58.8,70.5 57.8,70.53 57.09,71.1L50.39,76.56C49.62,77.2 48.44,76.84 48.15,75.88L45.78,68.28C44.34,63.64 40.83,59.93 36.28,58.23L31.48,56.44C30.26,55.98 30.25,54.26 31.46,53.79L80.79,34.76C81.83,34.36 82.91,35.27 82.68,36.37Z";
static NSString *const kTgFoldPath =
	@"M72.44,42.68L46.59,58.76C45.59,59.38 45.13,60.59 45.45,61.72L48.24,71.64C48.44,72.34 49.45,72.27 49.55,71.55L50.27,66.11C50.41,65.08 50.9,64.14 51.65,63.43L72.98,43.4C73.38,43.03 72.9,42.39 72.44,42.68Z";

static UIView *
SocialIcon(CGRect frame, NSString *glyphPath, NSString *foldPath)
{
	UIView *v = [[UIView alloc] initWithFrame:frame];
	// square bg: #19ffffff -> #00ffffff diagonal
	[v.layer addSublayer:GradientPathLayer(kSocialSquarePath, frame.size,
		CGPointMake(0.94, 0.042), CGPointMake(0.308, 1.121),
		[UIColor colorWithWhite:1.0 alpha:0.10], [UIColor colorWithWhite:1.0 alpha:0.0], 1.0)];
	// glyph: #ffffefdd -> #00ffefdd at 80% alpha
	CGPoint g0 = foldPath ? CGPointMake(0.166, 0.173) : CGPointMake(0.134, 0.224);
	CGPoint g1 = foldPath ? CGPointMake(0.997, 1.138) : CGPointMake(0.718, 1.208);
	UIColor *cream = [UIColor colorWithRed:1.0 green:0.937 blue:0.867 alpha:1.0];
	[v.layer addSublayer:GradientPathLayer(glyphPath, frame.size, g0, g1, cream,
		[UIColor colorWithRed:1.0 green:0.937 blue:0.867 alpha:0.0], 0.8)];
	if (foldPath)
		[v.layer addSublayer:GradientPathLayer(foldPath, frame.size, g0, g1, cream,
			[UIColor colorWithRed:1.0 green:0.937 blue:0.867 alpha:0.0], 0.8)];
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

// one server item, matching the reference screenshot (launcher_servers_item)
// decorate=NO -> no char/recommended icons (used for the main-screen panel)
static UIView *
ServerItem(CGSize size, NSInteger idx, BOOL decorate, void (^onSelect)(NSInteger))
{
	CGFloat iw = size.width, ih = size.height;
	UIView *item = PanelRect(CGRectMake(0, 0, iw, ih),
		[UIColor colorWithWhite:0.0 alpha:0.12], iw * 0.060,
		[UIColor colorWithWhite:1.0 alpha:0.22], MAX(1.0, iw * 0.006));

	// gold badge with number (shifted a touch right on the main panel)
	UIImage *goldImg = LoadLauncherImg(@"launcher_servers_item_gold_bg.webp");
	CGFloat bw = ih * 0.63;
	CGFloat bx = iw * (decorate ? 0.03 : 0.055);
	UIView *badge;
	if (goldImg) {
		badge = [[UIImageView alloc] initWithImage:goldImg];
		badge.frame = CGRectMake(bx, (ih - bw) / 2, bw, bw);
		badge.contentMode = UIViewContentModeScaleToFill;
		badge.layer.cornerRadius = bw * 0.22;
		badge.clipsToBounds = YES;
	} else {
		badge = PanelRect(CGRectMake(bx, (ih - bw) / 2, bw, bw),
			[UIColor colorWithRed:0.97 green:0.80 blue:0.18 alpha:1.0], bw * 0.22, nil, 0);
	}
	[badge addSubview:Label(badge.bounds,
		[NSString stringWithFormat:@"%ld", (long)(idx + 1)], bw * 0.5,
		[UIColor colorWithRed:0x4d/255.0 green:0x37/255.0 blue:0x09/255.0 alpha:1.0], YES, YES)];
	[item addSubview:badge];

	// name + red subtitle
	CGFloat nx = iw * 0.36, nw = iw * 0.60;
	[item addSubview:Label(CGRectMake(nx, ih * 0.15, nw, ih * 0.26),
		ServerName(idx), ih * 0.19, [UIColor whiteColor], YES, NO)];
	[item addSubview:Label(CGRectMake(nx, ih * 0.42, nw, ih * 0.16),
		@(g_servers[idx].sub), ih * 0.105,
		[UIColor colorWithRed:1.0 green:0.42 blue:0.42 alpha:1.0], YES, NO)];

	// progress + online count
	CGFloat pw = iw * 0.25, ph = MAX(3.0, ih * 0.045);
	CGFloat py = ih * 0.72;
	UIView *track = PanelRect(CGRectMake(nx, py, pw, ph),
		[UIColor colorWithWhite:1.0 alpha:0.35], ph / 2, nil, 0);
	[track addSubview:PanelRect(CGRectMake(0, 0, MAX(ph, pw * g_servers[idx].load), ph),
		[UIColor whiteColor], ph / 2, nil, 0)];
	[item addSubview:track];
	[item addSubview:Label(CGRectMake(nx + pw + iw * 0.04, py - ih * 0.06, iw * 0.28, ph + ih * 0.12),
		@"1/1000", ih * 0.15, [UIColor whiteColor], YES, NO)];

	// person icon (characters exist) top-right + recommended green corner
	if (decorate) {
		UIImageView *ch = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_servers_item_char_ic.webp")];
		CGFloat cw = ih * 0.24;
		ch.frame = CGRectMake(iw * 0.84, ih * 0.10, cw, cw);
		ch.contentMode = UIViewContentModeScaleAspectFit;
		[item addSubview:ch];

		UIImageView *rec = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_servers_item_recommended_ic.webp")];
		CGFloat rw = ih * 0.28;
		rec.frame = CGRectMake(iw * 0.905, ih * 0.72, rw, rw);
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
ShowServers(UIView *root);

static void
SelectServerAndUpdate(NSInteger sel, UIView *root)
{
	g_selectedServer = sel;
	if (g_mainPanelHolder) {
		for (UIView *v in [NSArray arrayWithArray:g_mainPanelHolder.subviews])
			[v removeFromSuperview];
		UIView *it = ServerItem(g_mainPanelHolder.bounds.size, sel, NO, ^(NSInteger s) {
			(void)s;
			ShowServers(root);
		});
		it.frame = g_mainPanelHolder.bounds;
		it.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[g_mainPanelHolder addSubview:it];
	}
	HideServers(root);
}

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

	// bg art + smooth blur + dark overlay (#99000000 like the XML)
	[scr addSubview:BgView(b, @"launcher_main_bg.webp", UIViewContentModeScaleAspectFill)];
	[scr addSubview:SmoothBlurOverlay(b)];
	[scr addSubview:PanelRect(b, [UIColor colorWithRed:0 green:0 blue:0 alpha:0.35], 0, nil, 0)];

	// back button (UIImageView needs userInteractionEnabled!)
	UIImageView *back = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_servers_back_btn.webp")];
	CGFloat bh2 = H * 0.095;
	CGFloat bw2 = bh2 * (back.image ? back.image.size.width / back.image.size.height : 2.2);
	back.frame = CGRectMake(W * 0.02, H * 0.033, bw2, bh2);
	back.contentMode = UIViewContentModeScaleAspectFit;
	back.userInteractionEnabled = YES;
	[scr addSubview:back];

	// centered title
	[scr addSubview:Label(CGRectMake(W * 0.30, H * 0.052, W * 0.40, H * 0.055),
		@"ВЫБОР СЕРВЕРА", H * 0.044, [UIColor whiteColor], YES, YES)];

	// item geometry from the reference: 26.2%W x 16.1%H
	CGFloat iw = W * 0.262, ih = H * 0.161;

	// favourites row (server with created characters)
	[scr addSubview:Label(CGRectMake(W * 0.0525, H * 0.155, W * 0.35, H * 0.045),
		@"Избранные сервера:", H * 0.029, [UIColor whiteColor], YES, NO)];
	UIView *favItem = ServerItem(CGSizeMake(iw, ih), 0, YES, ^(NSInteger sel) {
		SelectServerAndUpdate(sel, root);
	});
	favItem.frame = CGRectMake(W * 0.0525, H * 0.233, iw, ih);
	[scr addSubview:favItem];

	// all servers grid (3 columns, scrolls)
	[scr addSubview:Label(CGRectMake(W * 0.0525, H * 0.425, W * 0.35, H * 0.045),
		@"Все сервера:", H * 0.029, [UIColor whiteColor], YES, NO)];

	UIScrollView *grid = [[UIScrollView alloc] initWithFrame:CGRectMake(W * 0.0525, H * 0.505, W * 0.879, H * 0.36)];
	grid.showsVerticalScrollIndicator = NO;
	grid.alwaysBounceVertical = YES;
	CGFloat gapX = (W * 0.879 - 3 * iw) / 2, gapY = H * 0.025;
	for (int i = 0; i < g_serverCount; i++) {
		int row = i / 3, col = i % 3;
		UIView *it = ServerItem(CGSizeMake(iw, ih), i, YES, ^(NSInteger sel) {
			SelectServerAndUpdate(sel, root);
		});
		it.frame = CGRectMake(col * (iw + gapX), row * (ih + gapY), iw, ih);
		[grid addSubview:it];
	}
	int rows = (g_serverCount + 2) / 3;
	grid.contentSize = CGSizeMake(W * 0.879, rows * ih + (rows - 1) * gapY);
	[scr addSubview:grid];

	// legend pills at the bottom center
	{
		CGFloat pillH = H * 0.055, font = H * 0.021, iconSz = pillH * 0.55;
		UIColor *pillBg = [UIColor colorWithRed:0.13 green:0.32 blue:0.13 alpha:0.92];
		UIColor *white = [UIColor whiteColor];

		NSString *txt1 = @"- РЕКОМЕНДОВАННЫЙ СЕРВЕР";
		NSString *txt2 = @"- СЕРВЕР НА КОТОРОМ СОЗДАНЫ ПЕРСОНАЖИ";
		CGFloat w1 = txt1.length * font * 0.62 + iconSz + font * 2.2;
		CGFloat w2 = txt2.length * font * 0.62 + iconSz + font * 2.2;
		CGFloat x1 = W / 2 - (w1 + W * 0.012 + w2) / 2, yP = H - pillH - H * 0.015;

		UIView *p1 = PanelRect(CGRectMake(x1, yP, w1, pillH), pillBg, pillH / 2, nil, 0);
		UIImageView *ic1 = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_servers_item_recommended_ic.webp")];
		ic1.frame = CGRectMake(font * 0.7, (pillH - iconSz) / 2, iconSz, iconSz);
		ic1.contentMode = UIViewContentModeScaleAspectFit;
		[p1 addSubview:ic1];
		[p1 addSubview:Label(CGRectMake(font * 0.7 + iconSz + font * 0.4, 0, w1 - iconSz - font * 1.8, pillH),
			txt1, font, white, YES, NO)];
		[scr addSubview:p1];

		UIView *p2 = PanelRect(CGRectMake(x1 + w1 + W * 0.012, yP, w2, pillH), pillBg, pillH / 2, nil, 0);
		UIImageView *ic2 = [[UIImageView alloc] initWithImage:LoadLauncherImg(@"launcher_servers_item_char_ic.webp")];
		ic2.frame = CGRectMake(font * 0.7, (pillH - iconSz) / 2, iconSz, iconSz);
		ic2.contentMode = UIViewContentModeScaleAspectFit;
		[p2 addSubview:ic2];
		[p2 addSubview:Label(CGRectMake(font * 0.7 + iconSz + font * 0.4, 0, w2 - iconSz - font * 1.8, pillH),
			txt2, font, white, YES, NO)];
		[scr addSubview:p2];
	}

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

	// blurred background art (like the reference loader): art + system blur + tint
	[ldr addSubview:BgView(b, @"launcher_main_bg.webp", UIViewContentModeScaleAspectFill)];
	[ldr addSubview:SmoothBlurOverlay(b)];
	[ldr addSubview:PanelRect(b, [UIColor colorWithRed:0 green:0 blue:0 alpha:0.30], 0, nil, 0)];

	// dashed spinner (stands in for the lottie loader_screen_progress)
	CGFloat d = H * 0.085;
	UIView *spinner = [[UIView alloc] initWithFrame:CGRectMake(W / 2 - d / 2, H * 0.47 - d / 2, d, d)];

	UIBezierPath *dash = [UIBezierPath bezierPath];
	int segs = 10;
	for (int i = 0; i < segs; i++) {
		CGFloat a0 = i * (2 * M_PI / segs);
		[dash addArcWithCenter:CGPointMake(d / 2, d / 2)
		                radius:d * 0.36
		            startAngle:a0
		              endAngle:a0 + (2 * M_PI / segs) * 0.52
		             clockwise:YES];
	}
	CAShapeLayer *ring = [CAShapeLayer layer];
	ring.path = dash.CGPath;
	ring.fillColor = nil;
	ring.strokeColor = [UIColor whiteColor].CGColor;
	ring.lineWidth = d * 0.10;
	ring.lineCap = kCALineCapRound;
	[spinner.layer addSublayer:ring];

	CABasicAnimation *rot = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
	rot.fromValue = @0.0;
	rot.toValue = @(2 * M_PI);
	rot.duration = 1.1;
	rot.repeatCount = HUGE_VALF;
	[ring addAnimation:rot forKey:@"spin"];
	[ldr addSubview:spinner];

	[ldr addSubview:Label(CGRectMake(W * 0.25, H * 0.47 + d / 2 + H * 0.025,
		W * 0.50, H * 0.036), @"ОЖИДАНИЕ ЗАГРУЗКИ", H * 0.028, [UIColor whiteColor], YES, YES)];

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
	UIView *swapSq = PanelRect(CGRectMake(W * 0.165, H * 0.033, H * 0.055, H * 0.055),
		[UIColor colorWithWhite:0.05 alpha:0.55], H * 0.014, nil, 0);
	[swapSq addSubview:Label(swapSq.bounds, @"⇄", H * 0.032, [UIColor whiteColor], YES, YES)];
	[launch addSubview:swapSq];

	// current server panel = a real launcher_servers_item (tap -> servers list)
	{
		g_mainPanelHolder = [[UIView alloc] initWithFrame:CGRectMake(W * 0.02, H * 0.094, W * 0.178, H * 0.109)];
		g_mainPanelHolder.userInteractionEnabled = YES;
		UIView *it = ServerItem(g_mainPanelHolder.bounds.size, g_selectedServer, NO, ^(NSInteger sel) {
			(void)sel;
			ShowServers(root);
		});
		it.frame = g_mainPanelHolder.bounds;
		it.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[g_mainPanelHolder addSubview:it];
		[launch addSubview:g_mainPanelHolder];
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

	// socials bottom-left (exact NORMSOURCE vector art)
	{
		CGFloat sw = W * 0.045, gap = W * 0.0225, sy = H - sw - H * 0.055;
		UIView *yt = SocialIcon(CGRectMake(W * 0.0225, sy, sw, sw), kYtGlyphPath, nil);
		UIView *vk = SocialIcon(CGRectMake(W * 0.0225 + sw + gap, sy, sw, sw), kVkGlyphPath, nil);
		UIView *tg = SocialIcon(CGRectMake(W * 0.0225 + (sw + gap) * 2, sy, sw, sw), kTgGlyphPath, kTgFoldPath);
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
		g_mainPanelHolder = nil;

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
