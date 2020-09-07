//
//  JPImageresizerFrameView.m
//  JPImageresizerView
//
//  Created by 周健平 on 2017/12/11.
//  Copyright © 2017年 周健平. All rights reserved.
//

#import "JPImageresizerFrameView.h"
#import "JPImageresizerBlurView.h"
#import "UIImage+JPImageresizer.h"
#import "CALayer+JPImageresizer.h"

@interface JPImageresizerProxy : NSProxy
+ (instancetype)proxyWithTarget:(id)target;
@property (nonatomic, weak) id target;
@end

@implementation JPImageresizerProxy
+ (instancetype)proxyWithTarget:(id)target {
    JPImageresizerProxy *proxy = [self alloc];
    proxy.target = target;
    return proxy;
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    return [self.target methodSignatureForSelector:sel];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation invokeWithTarget:self.target];
}
@end

#define JPGridCount 3

typedef NS_ENUM(NSUInteger, JPDotRegion) {
    JPDR_Center,
    JPDR_LeftTop,
    JPDR_LeftMid,
    JPDR_LeftBottom,
    JPDR_RightTop,
    JPDR_RightMid,
    JPDR_RightBottom,
    JPDR_TopMid,
    JPDR_BottomMid
};

@interface JPImageresizerFrameView ()
@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, weak) UIScrollView *scrollView;
@property (nonatomic, weak) UIImageView *imageView;
@property (nonatomic, weak) JPImageresizerBlurView *blurView;
@property (nonatomic, weak) UIImageView *borderImageView;
- (CGRect)borderImageViewFrame;

// 遮罩图层
@property (nonatomic, weak) CAShapeLayer *maskLayer;
// 线框图层
@property (nonatomic, weak) CAShapeLayer *frameLayer;
// 左右上中下点图层
@property (nonatomic, weak) CAShapeLayer *dotsLayer;
// 网格线图层
@property (nonatomic, weak) CAShapeLayer *gridlinesLayer;

@property (nonatomic, assign) CGRect originImageFrame;
@property (nonatomic, assign) CGRect maxResizeFrame;
- (CGFloat)maxResizeX;
- (CGFloat)maxResizeY;
- (CGFloat)maxResizeW;
- (CGFloat)maxResizeH;

@property (nonatomic) CGFloat imageresizeX;
@property (nonatomic) CGFloat imageresizeY;
@property (nonatomic) CGFloat imageresizeW;
@property (nonatomic) CGFloat imageresizeH;
- (CGSize)imageresizerSize;
- (CGSize)imageViewSzie;
@end

@implementation JPImageresizerFrameView
{
    CGFloat _frameLayerLineW;
    
    CGFloat _dotWH;
    CGFloat _halfDotWH;
    
    CGFloat _arrLineW;
    CGFloat _halfArrLineW;
    CGFloat _arrLength;
    CGFloat _midArrLength;
    
    CGFloat _scopeWH;
    CGFloat _halfScopeWH;
    
    CGFloat _minImageWH;
    CGFloat _baseImageW;
    CGFloat _baseImageH;
    CGFloat _startResizeW;
    CGFloat _startResizeH;
    CGFloat _originWHScale;
    
    BOOL _isHideGridlines;
    BOOL _isArbitrarily;
    BOOL _isToBeArbitrarily;
    
    NSString *_kCAMediaTimingFunction;
    UIViewAnimationOptions _animationOption;
    NSTimeInterval _defaultDuration;
    NSTimeInterval _blurDuration;
    
    JPDotRegion _currDR;
    CGPoint _diagonal;
    
    BOOL _isRound;
}

#pragma mark - setter

- (void)setOriginImageFrame:(CGRect)originImageFrame {
    _originImageFrame = originImageFrame;
    _originWHScale = originImageFrame.size.width / originImageFrame.size.height;
}

- (void)setStrokeColor:(UIColor *)strokeColor {
    _strokeColor = strokeColor;
    [self __updateShapeLayersStrokeColor];
}

- (void)setBlurEffect:(UIBlurEffect *)blurEffect {
    [self.blurView setBlurEffect:blurEffect duration:0];
}

- (void)setBgColor:(UIColor *)bgColor {
    [self.blurView setBgColor:bgColor duration:0];
    self.superview.layer.backgroundColor = bgColor.CGColor;
}

- (void)setMaskAlpha:(CGFloat)maskAlpha {
    [self.blurView setMaskAlpha:maskAlpha duration:0];
}

- (void)setImageresizerFrame:(CGRect)imageresizerFrame {
    [self __updateImageresizerFrame:imageresizerFrame animateDuration:-1.0];
}

- (void)setImageresizeX:(CGFloat)imageresizeX {
    _imageresizerFrame.origin.x = imageresizeX;
}

- (void)setImageresizeY:(CGFloat)imageresizeY {
    _imageresizerFrame.origin.y = imageresizeY;
}

- (void)setImageresizeW:(CGFloat)imageresizeW {
    _imageresizerFrame.size.width = imageresizeW;
}

- (void)setImageresizeH:(CGFloat)imageresizeH {
    _imageresizerFrame.size.height = imageresizeH;
}

- (void)setResizeWHScale:(CGFloat)resizeWHScale {
    [self setResizeWHScale:resizeWHScale isToBeArbitrarily:NO animated:NO];
}

- (void)setResizeWHScale:(CGFloat)resizeWHScale isToBeArbitrarily:(BOOL)isToBeArbitrarily animated:(BOOL)isAnimated {
    if (_isRound) {
        [self setIsRound:NO animated:isAnimated];
        _resizeWHScale += 1;
    }
    if (resizeWHScale > 0 && [self __isHorizontalDirection:_rotationDirection]) resizeWHScale = 1.0 / resizeWHScale;
    if (_resizeWHScale == resizeWHScale && !isToBeArbitrarily) return;
    _resizeWHScale = resizeWHScale;
    _isArbitrarily = resizeWHScale <= 0;
    _isToBeArbitrarily = isToBeArbitrarily;
    if (self.superview) {
        CGRect adjustResizeFrame = [self __adjustResizeFrame];
        NSTimeInterval duration = isAnimated ? _defaultDuration : -1.0;
        _imageresizerFrame = adjustResizeFrame;
        [self __adjustImageresizerFrame:adjustResizeFrame isAdvanceUpdateOffset:NO animateDuration:duration];
    }
}

- (void)roundResize:(BOOL)isAnimated {
    if (_isRound) return;
    [self setIsRound:YES animated:isAnimated];
    _resizeWHScale = 1;
    _isArbitrarily = NO;
    _isToBeArbitrarily = NO;
    if (self.superview) {
        CGRect adjustResizeFrame = [self __adjustResizeFrame];
        _imageresizerFrame = adjustResizeFrame;
        [self __adjustImageresizerFrame:adjustResizeFrame isAdvanceUpdateOffset:NO animateDuration:_defaultDuration];
    }
}

- (void)setIsRound:(BOOL)isRound animated:(BOOL)isAnimated {
    _isRound = isRound;
    
    if (isRound) {
        _frameLayerLineW = 1.5;
        _dotWH =  0.0;
        _halfDotWH = 0.0;
        _halfArrLineW = 0.0;
        _arrLength = 0.0;
        _midArrLength = 0.0;
    } else {
        _frameLayerLineW = _borderImage ? 0.0 : 1.0;
        _dotWH =  12.0;
        _halfDotWH = _dotWH * 0.5;
        _halfArrLineW = _arrLineW * 0.5;
        _arrLength = 20.0;
        _midArrLength = _arrLength * 0.85;
    }
    
    if (_borderImage) {
        CGFloat alpha = (isRound || _isPreview) ? 0 : 1;
        CGFloat lineWidth = _frameLayerLineW;
        void (^animations)(void) = ^{
            self.borderImageView.alpha = alpha;
            self.frameLayer.lineWidth = lineWidth;
        };
        if (isAnimated) {
            [UIView animateWithDuration:_defaultDuration delay:0 options:_animationOption animations:animations completion:nil];
        } else {
            animations();
        }
    } else {
        self.frameLayer.lineWidth = _frameLayerLineW;
        [self __updateShapeLayersOpacity];
    }
}

- (BOOL)isRoundResizing {
    return _isRound;
}

- (void)setIsPreview:(BOOL)isPreview {
    [self setIsPreview:isPreview animated:NO];
}

- (void)setIsPreview:(BOOL)isPreview animated:(BOOL)isAnimated {
    _isPreview = isPreview;
    self.userInteractionEnabled = !isPreview;
    
    CGFloat opacity = _isPreview ? 0 : 1;
    CGFloat otherOpacity = _isRound ? 0 : opacity;
    
    if (isAnimated) {
        NSTimeInterval duration = _defaultDuration;
        CAMediaTimingFunctionName timingFunctionName = _kCAMediaTimingFunction;
        [UIView animateWithDuration:duration delay:0 options:_animationOption animations:^{
            [self.blurView setIsMaskAlpha:!isPreview duration:0];
        } completion:nil];
        if (_borderImage) {
            BOOL isRound = _isRound;
            [UIView animateWithDuration:duration delay:0 options:_animationOption animations:^{
                self.borderImageView.alpha = isRound ? 0 : opacity;
                self.frameLayer.opacity = isRound ? opacity : 0;
            } completion:nil];
        } else {
            void (^layerOpacityAnimate)(CALayer *layer, id toValue) = ^(CALayer *layer, id toValue) {
                if (!layer) return;
                [layer jpir_addBackwardsAnimationWithKeyPath:@"opacity" fromValue:@(layer.opacity) toValue:toValue timingFunctionName:timingFunctionName duration:duration];
            };
            layerOpacityAnimate(_frameLayer, @(opacity));
            layerOpacityAnimate(_dotsLayer, @(otherOpacity));
            if (_frameType == JPClassicFrameType) layerOpacityAnimate(_gridlinesLayer, @(otherOpacity));
        }
    } else {
        [self.blurView setIsMaskAlpha:!isPreview duration:0];
        _borderImageView.alpha = _isRound ? 0 : opacity;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self __setupShapeLayersOpacity:opacity];
    [CATransaction commit];
}

- (void)setBorderImage:(UIImage *)borderImage {
    _borderImage = borderImage;
    if (borderImage) {
        self.borderImageView.image = borderImage;
        _borderImageView.alpha = (_isPreview || _isRound) ? 0.0 : 1.0;
        _frameLayerLineW = _isRound ? 1.5 : 0.0;
    } else {
        [_borderImageView removeFromSuperview];
        _frameLayerLineW = _isRound ? 1.5 : 1.0;
    }
    [self setFrameType:_frameType];
}

- (void)setBorderImageRectInset:(CGPoint)borderImageRectInset {
    _borderImageRectInset = borderImageRectInset;
    _borderImageView.frame = self.borderImageViewFrame;
}

- (void)setFrameType:(JPImageresizerFrameType)frameType {
    _frameType = frameType;
    
    self.frameLayer.lineWidth = _frameLayerLineW;
    
    if (_borderImage) {
        [_dotsLayer removeFromSuperlayer];
        [_gridlinesLayer removeFromSuperlayer];
        [self __updateShapeLayersStrokeColor];
        return;
    }
    
    if (frameType == JPConciseFrameType) {
        [_gridlinesLayer removeFromSuperlayer];
        self.dotsLayer.lineWidth = 0;
    } else {
        [self gridlinesLayer];
        self.dotsLayer.lineWidth = _arrLineW;
    }
    
    [self __updateShapeLayersStrokeColor];
    [self __updateShapeLayersOpacity];
    
    if (!CGRectIsEmpty(_imageresizerFrame)) {
        [self __updateImageresizerFrame:_imageresizerFrame animateDuration:0];
    }
}

- (void)setAnimationCurve:(JPAnimationCurve)animationCurve {
    _animationCurve = animationCurve;
    switch (animationCurve) {
        case JPAnimationCurveEaseInOut:
            _kCAMediaTimingFunction = kCAMediaTimingFunctionEaseInEaseOut;
            _animationOption = UIViewAnimationOptionCurveEaseInOut;
            break;
        case JPAnimationCurveEaseIn:
            _kCAMediaTimingFunction = kCAMediaTimingFunctionEaseIn;
            _animationOption = UIViewAnimationOptionCurveEaseIn;
            break;
        case JPAnimationCurveEaseOut:
            _kCAMediaTimingFunction = kCAMediaTimingFunctionEaseOut;
            _animationOption = UIViewAnimationOptionCurveEaseOut;
            break;
        case JPAnimationCurveLinear:
            _kCAMediaTimingFunction = kCAMediaTimingFunctionLinear;
            _animationOption = UIViewAnimationOptionCurveLinear;
            break;
    }
}

- (void)setIsCanRecovery:(BOOL)isCanRecovery {
    _isCanRecovery = isCanRecovery;
    !self.imageresizerIsCanRecovery ? : self.imageresizerIsCanRecovery(isCanRecovery);
}

- (void)setIsPrepareToScale:(BOOL)isPrepareToScale {
    _isPrepareToScale = isPrepareToScale;
    !self.imageresizerIsPrepareToScale ? : self.imageresizerIsPrepareToScale(isPrepareToScale);
}

- (void)setInitialResizeWHScale:(CGFloat)initialResizeWHScale {
    if (initialResizeWHScale < 0.0) initialResizeWHScale = 0.0;
    _initialResizeWHScale = initialResizeWHScale;
    [self __checkIsCanRecovery];
}

- (void)setIsShowMidDots:(BOOL)isShowMidDots {
    if (_isShowMidDots == isShowMidDots) return;
    _isShowMidDots = isShowMidDots;
    if (_borderImage || _isPreview) return;
    if (!CGRectIsEmpty(_imageresizerFrame)) {
        [self __updateImageresizerFrame:_imageresizerFrame animateDuration:0];
    }
}

#pragma mark - getter

- (NSTimeInterval)defaultDuration {
    return _defaultDuration;
}

- (CGFloat)maxResizeX {
    return self.maxResizeFrame.origin.x;
}

- (CGFloat)maxResizeY {
    return self.maxResizeFrame.origin.y;
}

- (CGFloat)maxResizeW {
    return self.maxResizeFrame.size.width;
}

- (CGFloat)maxResizeH {
    return self.maxResizeFrame.size.height;
}

- (CGFloat)imageresizeX {
    return _imageresizerFrame.origin.x;
}

- (CGFloat)imageresizeY {
    return _imageresizerFrame.origin.y;
}

- (CGFloat)imageresizeW {
    return _imageresizerFrame.size.width;
}

- (CGFloat)imageresizeH {
    return _imageresizerFrame.size.height;
}

- (CGSize)imageresizerSize {
    CGFloat w = ((NSInteger)(self.imageresizerFrame.size.width)) * 1.0;
    CGFloat h = ((NSInteger)(self.imageresizerFrame.size.height)) * 1.0;
    return CGSizeMake(w, h);
}

- (CGSize)imageViewSzie {
    CGFloat w = ((NSInteger)(self.imageView.frame.size.width)) * 1.0;
    CGFloat h = ((NSInteger)(self.imageView.frame.size.height)) * 1.0;
    return [self __isHorizontalDirection:_rotationDirection] ? CGSizeMake(h, w) : CGSizeMake(w, h);
}

- (CAShapeLayer *)frameLayer {
    if (!_frameLayer) {
        _frameLayer = [self __createShapeLayer:1.0];
        _frameLayer.fillColor = [UIColor clearColor].CGColor;
    }
    return _frameLayer;
}

- (CAShapeLayer *)dotsLayer {
    if (!_dotsLayer) _dotsLayer = [self __createShapeLayer:0];
    return _dotsLayer;
}

- (CAShapeLayer *)gridlinesLayer {
    if (!_gridlinesLayer) _gridlinesLayer = [self __createShapeLayer:0.5];
    return _gridlinesLayer;
}

- (BOOL)edgeLineIsEnabled {
    if (_isArbitrarily) {
        return _edgeLineIsEnabled;
    } else {
        return NO;
    }
}

- (UIImageView *)borderImageView {
    if (!_borderImageView) {
        UIImageView *borderImageView = [[UIImageView alloc] initWithFrame:self.borderImageViewFrame];
        borderImageView.layer.minificationFilter = kCAFilterNearest;
        borderImageView.layer.magnificationFilter = kCAFilterNearest;
        [self addSubview:borderImageView];
        _borderImageView = borderImageView;
    }
    return _borderImageView;
}

- (CGRect)borderImageViewFrame {
    if (!CGRectIsEmpty(_imageresizerFrame)) {
        return CGRectInset(_imageresizerFrame, _borderImageRectInset.x, _borderImageRectInset.y);
    }
    return CGRectZero;
}

- (UIBlurEffect *)blurEffect {
    return self.blurView.blurEffect;
}

- (UIColor *)bgColor {
    return self.blurView.bgColor;
}

- (CGFloat)maskAlpha {
    return self.blurView.maskAlpha;
}

#pragma mark - init

- (instancetype)initWithFrame:(CGRect)frame
           baseContentMaxSize:(CGSize)baseContentMaxSize
                    frameType:(JPImageresizerFrameType)frameType
               animationCurve:(JPAnimationCurve)animationCurve
                   blurEffect:(UIBlurEffect *)blurEffect
                      bgColor:(UIColor *)bgColor
                    maskAlpha:(CGFloat)maskAlpha
                  strokeColor:(UIColor *)strokeColor
                resizeWHScale:(CGFloat)resizeWHScale
                   scrollView:(UIScrollView *)scrollView
                    imageView:(UIImageView *)imageView
                  borderImage:(UIImage *)borderImage
         borderImageRectInset:(CGPoint)borderImageRectInset
                isRoundResize:(BOOL)isRoundResize
                isShowMidDots:(BOOL)isShowMidDots
    imageresizerIsCanRecovery:(JPImageresizerIsCanRecoveryBlock)imageresizerIsCanRecovery
 imageresizerIsPrepareToScale:(JPImageresizerIsPrepareToScaleBlock)imageresizerIsPrepareToScale {
    
    if (self = [super initWithFrame:frame]) {
        self.clipsToBounds = NO;
        self.animationCurve = animationCurve;
        self.scrollView = scrollView;
        self.imageView = imageView;
        
        _defaultDuration = 0.27;
        _blurDuration = 0.3;
        _arrLineW = 2.5;
        _scopeWH = 50.0;
        _halfScopeWH = _scopeWH * 0.5;
        _minImageWH = 70.0;
        
        _edgeLineIsEnabled = YES;
        _rotationDirection = JPImageresizerVerticalUpDirection;
        _baseContentMaxSize = baseContentMaxSize;
        _imageresizerIsCanRecovery = [imageresizerIsCanRecovery copy];
        _imageresizerIsPrepareToScale = [imageresizerIsPrepareToScale copy];
        _strokeColor = strokeColor;
        _isShowMidDots = isShowMidDots;
        
        JPImageresizerBlurView *blurView = [[JPImageresizerBlurView alloc] initWithFrame:self.bounds blurEffect:blurEffect bgColor:bgColor maskAlpha:maskAlpha];
        blurView.userInteractionEnabled = NO;
        [self addSubview:blurView];
        self.blurView = blurView;
        
        CAShapeLayer *maskLayer = [CAShapeLayer layer];
        maskLayer.frame = blurView.bounds;
        maskLayer.fillColor = [UIColor blackColor].CGColor;
        maskLayer.fillRule = kCAFillRuleEvenOdd;
        blurView.layer.mask = maskLayer;
        self.maskLayer = maskLayer;
        
        _frameLayerLineW = isRoundResize ? 1.5 : (borderImage ? 0.0 : 1.0);
        _borderImageRectInset = borderImageRectInset;
        
        if (borderImage) {
            _frameType = frameType;
            self.borderImage = borderImage;
        } else {
            self.frameType = frameType;
        }
        
        if (isRoundResize) {
            [self roundResize:NO];
        } else {
            _dotWH = 12.0;
            _halfDotWH = _dotWH * 0.5;
            _halfArrLineW = _arrLineW * 0.5;
            _arrLength = 20.0;
            _midArrLength = _arrLength * 0.85;
            
            if (resizeWHScale == _resizeWHScale) _resizeWHScale = resizeWHScale + 1.0;
            self.resizeWHScale = resizeWHScale;
        }
        
        self.initialResizeWHScale = resizeWHScale;
        
        UIPanGestureRecognizer *panGR = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(__panHandle:)];
        [self addGestureRecognizer:panGR];
        _panGR = panGR;
    }
    return self;
}

#pragma mark - life cycle

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (self.superview) [self __updateImageOriginFrameWithDirection:_rotationDirection duration:-1.0];
}

- (void)dealloc {
    self.window.userInteractionEnabled = YES;
    [self __removeTimer];
}

#pragma mark - override method

#ifdef __IPHONE_13_0
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    self.strokeColor = _strokeColor;
    self.bgColor = self.blurView.bgColor;
}
#endif

#pragma mark - timer

- (BOOL)__addTimer {
    BOOL isHasTimer = [self __removeTimer];
    self.timer = [NSTimer timerWithTimeInterval:0.65 target:[JPImageresizerProxy proxyWithTarget:self] selector:@selector(__timerHandle) userInfo:nil repeats:NO]; // default 0.65
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    return isHasTimer;
}

- (BOOL)__removeTimer {
    if (self.timer) {
        [self.timer invalidate];
        self.timer = nil;
        return YES;
    }
    return NO;
}

- (void)__timerHandle {
    [self __removeTimer];
    [self __adjustImageresizerFrame:[self __adjustResizeFrame] isAdvanceUpdateOffset:YES animateDuration:_defaultDuration];
}

#pragma mark - assist method

- (CAShapeLayer *)__createShapeLayer:(CGFloat)lineWidth {
    CAShapeLayer *shapeLayer = [CAShapeLayer layer];
    shapeLayer.lineWidth = lineWidth;
    [self.layer addSublayer:shapeLayer];
    return shapeLayer;
}

- (BOOL)__isHorizontalDirection:(JPImageresizerRotationDirection)direction {
    return (direction == JPImageresizerHorizontalLeftDirection ||
            direction == JPImageresizerHorizontalRightDirection);
}

- (UIBezierPath *)__conciseDotsPathWithFrame:(CGRect)frame {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat halfDotWH = _halfDotWH;
    CGFloat dotWH = _dotWH;
    void (^appendPathBlock)(CGPoint point) = ^(CGPoint point){
        [path appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(point.x - halfDotWH, point.y - halfDotWH, dotWH, dotWH)]];
    };
    
    CGPoint originPoint = frame.origin;
    CGPoint midPoint = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    CGPoint maxPoint = CGPointMake(CGRectGetMaxX(frame), CGRectGetMaxY(frame));
    
    if (_isRound) {
        CGFloat radius = frame.size.width * 0.5;
        CGFloat rightAngleSide = sqrt((pow(radius, 2) * 0.5));
        appendPathBlock(CGPointMake(midPoint.x - rightAngleSide, midPoint.y - rightAngleSide));
        appendPathBlock(CGPointMake(midPoint.x - rightAngleSide, midPoint.y + rightAngleSide));
        appendPathBlock(CGPointMake(midPoint.x + rightAngleSide, midPoint.y - rightAngleSide));
        appendPathBlock(CGPointMake(midPoint.x + rightAngleSide, midPoint.y + rightAngleSide));
    } else {
        appendPathBlock(originPoint);
        appendPathBlock(CGPointMake(originPoint.x, maxPoint.y));
        appendPathBlock(CGPointMake(maxPoint.x, originPoint.y));
        appendPathBlock(CGPointMake(maxPoint.x, maxPoint.y));
    }
    
    if (_isShowMidDots) {
        appendPathBlock(CGPointMake(originPoint.x, midPoint.y));
        appendPathBlock(CGPointMake(maxPoint.x, midPoint.y));
        appendPathBlock(CGPointMake(midPoint.x, originPoint.y));
        appendPathBlock(CGPointMake(midPoint.x, maxPoint.y));
    }
    
    return path;
}

- (UIBezierPath *)__classicDotsPathWithFrame:(CGRect)frame {
    UIBezierPath *path = [UIBezierPath bezierPath];
    void (^appendPathBlock)(CGPoint point, CGPoint startPoint, CGPoint endPoint) = ^(CGPoint point, CGPoint startPoint, CGPoint endPoint) {
        [path moveToPoint:startPoint];
        [path addLineToPoint:point];
        [path addLineToPoint:endPoint];
    };
    
    CGPoint originPoint = frame.origin;
    CGPoint midPoint = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    CGPoint maxPoint = CGPointMake(CGRectGetMaxX(frame), CGRectGetMaxY(frame));
    CGFloat arrLength = _arrLength;
    CGFloat halfArrLineW = _halfArrLineW;
    CGPoint point;
    CGPoint startPoint;
    CGPoint endPoint;
    
    if (_isRound) {
        CGFloat radius = frame.size.width * 0.5;
        CGFloat rightAngleSide = sqrt((pow(radius, 2) * 0.5));

        point = CGPointMake(midPoint.x - rightAngleSide, midPoint.y - rightAngleSide);
        startPoint = CGPointMake(point.x, point.y + arrLength);
        endPoint = CGPointMake(point.x + arrLength, point.y);
        appendPathBlock(point, startPoint, endPoint);
        
        point = CGPointMake(midPoint.x - rightAngleSide, midPoint.y + rightAngleSide);
        startPoint = CGPointMake(point.x, point.y - arrLength);
        endPoint = CGPointMake(point.x + arrLength, point.y);
        appendPathBlock(point, startPoint, endPoint);
        
        point = CGPointMake(midPoint.x + rightAngleSide, midPoint.y - rightAngleSide);
        startPoint = CGPointMake(point.x - arrLength, point.y);
        endPoint = CGPointMake(point.x, point.y + arrLength);
        appendPathBlock(point, startPoint, endPoint);
        
        point = CGPointMake(midPoint.x + rightAngleSide, midPoint.y + rightAngleSide);
        startPoint = CGPointMake(point.x - arrLength, point.y);
        endPoint = CGPointMake(point.x, point.y - arrLength);
        appendPathBlock(point, startPoint, endPoint);
    } else {
        point = CGPointMake(originPoint.x - halfArrLineW, originPoint.y - halfArrLineW);
        startPoint = CGPointMake(point.x, point.y + arrLength);
        endPoint = CGPointMake(point.x + arrLength, point.y);
        appendPathBlock(point, startPoint, endPoint);
        
        point = CGPointMake(originPoint.x - halfArrLineW, maxPoint.y + halfArrLineW);
        startPoint = CGPointMake(point.x, point.y - arrLength);
        endPoint = CGPointMake(point.x + arrLength, point.y);
        appendPathBlock(point, startPoint, endPoint);
        
        point = CGPointMake(maxPoint.x + halfArrLineW, originPoint.y - halfArrLineW);
        startPoint = CGPointMake(point.x - arrLength, point.y);
        endPoint = CGPointMake(point.x, point.y + arrLength);
        appendPathBlock(point, startPoint, endPoint);
        
        point = CGPointMake(maxPoint.x + halfArrLineW, maxPoint.y + halfArrLineW);
        startPoint = CGPointMake(point.x - arrLength, point.y);
        endPoint = CGPointMake(point.x, point.y - arrLength);
        appendPathBlock(point, startPoint, endPoint);
    }
    
    if (_isShowMidDots) {
        arrLength = _midArrLength;
        
        point = CGPointMake(originPoint.x - halfArrLineW, midPoint.y);
        startPoint = CGPointMake(point.x, point.y - arrLength);
        endPoint = CGPointMake(point.x, point.y + arrLength);
        appendPathBlock(point, startPoint, endPoint);
        
        point = CGPointMake(maxPoint.x + halfArrLineW, midPoint.y);
        startPoint = CGPointMake(point.x, point.y - arrLength);
        endPoint = CGPointMake(point.x, point.y + arrLength);
        appendPathBlock(point, startPoint, endPoint);
        
        point = CGPointMake(midPoint.x, originPoint.y - halfArrLineW);
        startPoint = CGPointMake(point.x - arrLength, point.y);
        endPoint = CGPointMake(point.x + arrLength, point.y);
        appendPathBlock(point, startPoint, endPoint);
    
        point = CGPointMake(midPoint.x, maxPoint.y + halfArrLineW);
        startPoint = CGPointMake(point.x - arrLength, point.y);
        endPoint = CGPointMake(point.x + arrLength, point.y);
        appendPathBlock(point, startPoint, endPoint);
    }
    
    return path;
}

- (UIBezierPath *)__gridlineWithGridCount:(NSUInteger)gridCount frame:(CGRect)frame {
    if (gridCount <= 1) {
        return nil;
    }
    
    CGFloat x = frame.origin.x;
    CGFloat y = frame.origin.y;
    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;
    CGFloat horSpace = w / (1.0 * gridCount);
    CGFloat verSpace = h / (1.0 * gridCount);
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSInteger i = 1; i < gridCount; i++) {
        CGFloat px = x;
        CGFloat py = y + verSpace * i;
        [path moveToPoint:CGPointMake(px, py)];
        [path addLineToPoint:CGPointMake(px + w, py)];
        
        px = x + horSpace * i;
        py = y;
        [path moveToPoint:CGPointMake(px, py)];
        [path addLineToPoint:CGPointMake(px, py + h)];
    }
    
    return path;
}

- (BOOL)__imageresizerFrameIsEqualImageViewFrame {
    CGSize imageresizerSize = self.imageresizerSize;
    CGSize imageViewSzie = self.imageViewSzie;
    CGFloat resizeWHScale = [self __isHorizontalDirection:_rotationDirection] ? (1.0 / _resizeWHScale) : _resizeWHScale;
    if (_isArbitrarily || (resizeWHScale == _originWHScale)) {
        return (fabs(imageresizerSize.width - imageViewSzie.width) <= 1 &&
                fabs(imageresizerSize.height - imageViewSzie.height) <= 1);
    } else {
        return (fabs(imageresizerSize.width - imageViewSzie.width) <= 1 ||
                fabs(imageresizerSize.height - imageViewSzie.height) <= 1);
    }
}

- (CGRect)__baseImageresizerFrame {
    if (_isArbitrarily) {
        return self.originImageFrame;
    } else {
        CGFloat w = 0;
        CGFloat h = 0;
        if ([self __isHorizontalDirection:_rotationDirection]) {
            h = _baseImageW;
            w = h * _resizeWHScale;
            if (w > self.maxResizeW) {
                w = self.maxResizeW;
                h = w / _resizeWHScale;
            }
        } else {
            w = _baseImageW;
            h = w / _resizeWHScale;
            if (h > self.maxResizeH) {
                h = self.maxResizeH;
                w = h * _resizeWHScale;
            }
        }
        CGFloat x = self.maxResizeX + (self.maxResizeW - w) * 0.5;
        CGFloat y = self.maxResizeY + (self.maxResizeH - h) * 0.5;
        return CGRectMake(x, y, w, h);
    }
}

- (CGRect)__adjustResizeFrame {
    CGFloat resizeWHScale = _isArbitrarily ? (self.imageresizeW / self.imageresizeH) : _resizeWHScale;
    CGFloat adjustResizeW = 0;
    CGFloat adjustResizeH = 0;
    if (resizeWHScale >= 1) {
        adjustResizeW = self.maxResizeW;
        adjustResizeH = adjustResizeW / resizeWHScale;
        if (adjustResizeH > self.maxResizeH) {
            adjustResizeH = self.maxResizeH;
            adjustResizeW = self.maxResizeH * resizeWHScale;
        }
    } else {
        adjustResizeH = self.maxResizeH;
        adjustResizeW = adjustResizeH * resizeWHScale;
        if (adjustResizeW > self.maxResizeW) {
            adjustResizeW = self.maxResizeW;
            adjustResizeH = adjustResizeW / resizeWHScale;
        }
    }
    CGFloat adjustResizeX = self.maxResizeX + (self.maxResizeW - adjustResizeW) * 0.5;
    CGFloat adjustResizeY = self.maxResizeY + (self.maxResizeH - adjustResizeH) * 0.5;
    return CGRectMake(adjustResizeX, adjustResizeY, adjustResizeW, adjustResizeH);
}

#pragma mark - private method

- (void)__updateShapeLayersStrokeColor {
    CGColorRef strokeCGColor = _strokeColor.CGColor;
    _frameLayer.strokeColor = strokeCGColor;
    if (_borderImage) return;
    CGColorRef clearCGColor = [UIColor clearColor].CGColor;
    if (_frameType == JPConciseFrameType) {
        _dotsLayer.fillColor = strokeCGColor;
        _dotsLayer.strokeColor = clearCGColor;
    } else {
        _dotsLayer.fillColor = clearCGColor;
        _dotsLayer.strokeColor = strokeCGColor;
    }
    _gridlinesLayer.strokeColor = strokeCGColor;
}

- (void)__updateShapeLayersOpacity {
    [self __setupShapeLayersOpacity:(_isPreview ? 0 : 1)];
}
    
- (void)__setupShapeLayersOpacity:(CGFloat)opacity {
    _frameLayer.opacity = opacity;
    if (_borderImage || _isRound) opacity = 0;
    _dotsLayer.opacity = opacity;
    _gridlinesLayer.opacity = opacity;
}

- (void)__hideOrShowGridLines:(BOOL)isHide animateDuration:(NSTimeInterval)duration {
    if (_frameType != JPClassicFrameType || !_gridlinesLayer || _borderImage || _isRound) {
        _isHideGridlines = NO;
        return;
    }
    if (_isHideGridlines == isHide) return;
    _isHideGridlines = isHide;
    CGFloat toOpacity = isHide ? 0 : 1;
    if (duration > 0) {
        CGFloat fromOpacity = isHide ? 1 : 0;
        NSString *keyPath = @"opacity";
        CABasicAnimation *anim = [CABasicAnimation jpir_backwardsAnimationWithKeyPath:keyPath fromValue:@(fromOpacity) toValue:@(toOpacity) timingFunctionName:_kCAMediaTimingFunction duration:duration];
        [_gridlinesLayer addAnimation:anim forKey:keyPath];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _gridlinesLayer.opacity = toOpacity;
    [CATransaction commit];
}

- (void)__updateImageresizerFrame:(CGRect)imageresizerFrame animateDuration:(NSTimeInterval)duration {
    _imageresizerFrame = imageresizerFrame;
    
    CGFloat radius = _isRound ? imageresizerFrame.size.width * 0.5 : 0.1;
    
    UIBezierPath *framePath = [UIBezierPath bezierPathWithRoundedRect:imageresizerFrame cornerRadius:radius];
    
    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRect:self.blurView.bounds];
    [maskPath appendPath:framePath];
    
    if (_borderImage) {
        CGRect borderImageViewFrame = self.borderImageViewFrame;
        if (duration > 0) {
            CAMediaTimingFunctionName timingFunctionName = _kCAMediaTimingFunction;
            void (^layerPathAnimate)(CAShapeLayer *layer, UIBezierPath *path) = ^(CAShapeLayer *layer, UIBezierPath *path) {
                if (!layer) return;
                [layer jpir_addBackwardsAnimationWithKeyPath:@"path" fromValue:(id)layer.path toValue:path timingFunctionName:timingFunctionName duration:duration];
            };
            
            [UIView animateWithDuration:duration delay:0 options:_animationOption animations:^{
                self.borderImageView.frame = borderImageViewFrame;
            } completion:nil];
            layerPathAnimate(_maskLayer, maskPath);
            layerPathAnimate(_frameLayer, framePath);
        } else {
            _borderImageView.frame = borderImageViewFrame;
        }
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _maskLayer.path = maskPath.CGPath;
        _frameLayer.path = framePath.CGPath;
        [CATransaction commit];
        return;
    }
    
    UIBezierPath *dotsPath;
    UIBezierPath *gridlinesPath;
    
    BOOL isClassicFrameType = _frameType == JPClassicFrameType;
    if (isClassicFrameType) {
        dotsPath = [self __classicDotsPathWithFrame:imageresizerFrame];
        gridlinesPath = [self __gridlineWithGridCount:JPGridCount frame:imageresizerFrame];
    } else {
        dotsPath = [self __conciseDotsPathWithFrame:imageresizerFrame];
    }
    
    if (duration > 0) {
        CAMediaTimingFunctionName timingFunctionName = _kCAMediaTimingFunction;
        void (^layerPathAnimate)(CAShapeLayer *layer, UIBezierPath *path) = ^(CAShapeLayer *layer, UIBezierPath *path) {
            if (!layer) return;
            [layer jpir_addBackwardsAnimationWithKeyPath:@"path" fromValue:(id)layer.path toValue:path timingFunctionName:timingFunctionName duration:duration];
        };
        if (_dotsLayer.opacity) layerPathAnimate(_dotsLayer, dotsPath);
        if (isClassicFrameType && _gridlinesLayer.opacity) layerPathAnimate(_gridlinesLayer, gridlinesPath);
        layerPathAnimate(_maskLayer, maskPath);
        layerPathAnimate(_frameLayer, framePath);
    }
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _maskLayer.path = maskPath.CGPath;
    _frameLayer.path = framePath.CGPath;
    _dotsLayer.path = dotsPath.CGPath;
    if (isClassicFrameType) _gridlinesLayer.path = gridlinesPath.CGPath;
    [CATransaction commit];
}

- (void)__updateImageOriginFrameWithDirection:(JPImageresizerRotationDirection)rotationDirection duration:(NSTimeInterval)duration {
    [self __removeTimer];
    _baseImageW = self.imageView.bounds.size.width;
    _baseImageH = self.imageView.bounds.size.height;
    CGFloat x = (self.bounds.size.width - _baseImageW) * 0.5;
    CGFloat y = (self.bounds.size.height - _baseImageH) * 0.5;
    self.originImageFrame = CGRectMake(x, y, _baseImageW, _baseImageH);
    [self __updateRotationDirection:rotationDirection];
    _imageresizerFrame = [self __baseImageresizerFrame];
    [self __adjustImageresizerFrame:[self __adjustResizeFrame] isAdvanceUpdateOffset:YES animateDuration:duration];
}

- (void)__updateRotationDirection:(JPImageresizerRotationDirection)rotationDirection {
    [self __updateMaxResizeFrameWithDirection:rotationDirection];
    if (!_isArbitrarily) {
        BOOL isSwitchVerHor = [self __isHorizontalDirection:_rotationDirection] != [self __isHorizontalDirection:rotationDirection];
        if (isSwitchVerHor) _resizeWHScale = 1.0 / _resizeWHScale;
    }
    _rotationDirection = rotationDirection;
}

- (void)__updateMaxResizeFrameWithDirection:(JPImageresizerRotationDirection)direction {
    CGFloat w = _baseContentMaxSize.width;
    CGFloat h = _baseContentMaxSize.height;
    if ([self __isHorizontalDirection:direction]) {
        w = _baseContentMaxSize.height;
        h = _baseContentMaxSize.width;
    }
    CGFloat x = (self.bounds.size.width - w) * 0.5;
    CGFloat y = (self.bounds.size.height - h) * 0.5;
    self.maxResizeFrame = CGRectMake(x, y, w, h);
    
    if (_rotationDirection == direction) return;
    
    self.frameLayer.lineWidth = _frameLayerLineW;
    
    if (_borderImage) return;
    
    if (_frameType == JPClassicFrameType) {
        _gridlinesLayer.lineWidth = 0.5;
        _dotsLayer.lineWidth = _arrLineW;
    } else {
        _dotsLayer.lineWidth = 0;
    }
}

- (void)__adjustImageresizerFrame:(CGRect)adjustResizeFrame
            isAdvanceUpdateOffset:(BOOL)isAdvanceUpdateOffset
                  animateDuration:(NSTimeInterval)duration {
    CGRect imageresizerFrame = self.imageresizerFrame;
    UIScrollView *scrollView = self.scrollView;
    UIImageView *imageView = self.imageView;
    
    // zoomFrame
    // 根据裁剪的区域，因为需要有间距，所以拼接成self的尺寸获取缩放的区域zoomFrame
    // 宽高比不变，所以宽度高度的比例是一样，这里就用宽度比例吧
    CGFloat convertScale = imageresizerFrame.size.width / adjustResizeFrame.size.width;
    CGFloat dx = -adjustResizeFrame.origin.x * convertScale;
    CGFloat dy = -adjustResizeFrame.origin.y * convertScale;
    CGRect convertZoomFrame = CGRectInset(imageresizerFrame, dx, dy);
    // 边沿检测，到顶就往外取值，防止有空隙
    CGRect convertImageresizerFrame = [self convertRect:imageresizerFrame toView:scrollView];
    BOOL isTheTop = fabs(convertImageresizerFrame.origin.y - imageView.frame.origin.y) < 1.0;
    BOOL isTheLead = fabs(convertImageresizerFrame.origin.x - imageView.frame.origin.x) < 1.0;
    BOOL isTheBottom = fabs(CGRectGetMaxY(convertImageresizerFrame) - CGRectGetMaxY(imageView.frame)) < 1.0;
    BOOL isTheTrail = fabs(CGRectGetMaxX(convertImageresizerFrame) - CGRectGetMaxX(imageView.frame)) < 1.0;
    if (isTheTop) convertZoomFrame.origin.y -= 1.0;
    if (isTheLead) convertZoomFrame.origin.x -= 1.0;
    if (isTheBottom) convertZoomFrame.size.height += 1.0;
    if (isTheTrail) convertZoomFrame.size.width += 1.0;
    CGRect zoomFrame = [self convertRect:convertZoomFrame toView:imageView];
    
    // contentInset
    UIEdgeInsets contentInset = [self __scrollViewContentInsetWithAdjustResizeFrame:adjustResizeFrame];
    
    // contentOffset
    CGPoint contentOffset = scrollView.contentOffset;
    if (isAdvanceUpdateOffset) {
        contentOffset = [self convertPoint:imageresizerFrame.origin toView:imageView];
        contentOffset.x = -contentInset.left + contentOffset.x * scrollView.zoomScale;
        contentOffset.y = -contentInset.top + contentOffset.y * scrollView.zoomScale;
    }
    
    // minimumZoomScale
    scrollView.minimumZoomScale = [self __scrollViewMinZoomScaleWithResizeSize:adjustResizeFrame.size];
    
    void (^zoomBlock)(void) = ^{
        [scrollView setContentInset:contentInset];
        if (isAdvanceUpdateOffset) {
            [scrollView setContentOffset:contentOffset animated:NO];
        }
        [scrollView zoomToRect:zoomFrame animated:NO];
        if (!isAdvanceUpdateOffset) {
            CGPoint offset = [self convertPoint:self.imageresizerFrame.origin toView:imageView];
            offset.x = -contentInset.left + offset.x * scrollView.zoomScale;
            offset.y = -contentInset.top + offset.y * scrollView.zoomScale;
            [scrollView setContentOffset:offset animated:NO];
        }
    };
    
    void (^completeBlock)(void) = ^{
        [self.blurView setIsBlur:YES duration:self->_blurDuration];
        self.superview.userInteractionEnabled = YES;
        if (self->_isToBeArbitrarily) {
            self->_isToBeArbitrarily = NO;
            self->_resizeWHScale = 0;
            self->_isArbitrarily = YES;
        }
        [self __checkIsCanRecovery];
        self.isPrepareToScale = NO;
    };
    
    self.superview.userInteractionEnabled = NO;
    [self __hideOrShowGridLines:NO animateDuration:_blurDuration];
    [self __updateImageresizerFrame:adjustResizeFrame animateDuration:duration];
    if (duration > 0) {
        [UIView animateWithDuration:duration delay:0 options:_animationOption animations:^{
            zoomBlock();
        } completion:^(BOOL finished) {
            if (finished) completeBlock();
        }];
    } else {
        zoomBlock();
        completeBlock();
    }
}

- (UIEdgeInsets)__scrollViewContentInsetWithAdjustResizeFrame:(CGRect)adjustResizeFrame {
    // scrollView宽高跟self一样，上下左右不需要额外添加Space
    CGFloat top = adjustResizeFrame.origin.y; // + veSpace?
    CGFloat bottom = self.bounds.size.height - CGRectGetMaxY(adjustResizeFrame); // + veSpace?
    CGFloat left = adjustResizeFrame.origin.x; // + hoSpace?
    CGFloat right = self.bounds.size.width - CGRectGetMaxX(adjustResizeFrame); // + hoSpace?
    return UIEdgeInsetsMake(top, left, bottom, right);
}

- (CGFloat)__scrollViewMinZoomScaleWithResizeSize:(CGSize)size {
    CGFloat length;
    CGFloat baseLength;
    CGFloat width;
    CGFloat baseWidth;
    if (size.width >= size.height) {
        length = size.width;
        baseLength = _baseImageW;
        width = size.height;
        baseWidth = _baseImageH;
    } else {
        length = size.height;
        baseLength = _baseImageH;
        width = size.width;
        baseWidth = _baseImageW;
    }
    CGFloat minZoomScale = length / baseLength;
    CGFloat scaleWidth = baseWidth * minZoomScale;
    if (scaleWidth < width) {
        minZoomScale *= (width / scaleWidth);
    }
    return minZoomScale;
}

- (void)__checkIsCanRecovery {
    if (self.resizeWHScale != self.initialResizeWHScale) {
        self.isCanRecovery = YES;
        return;
    }
    
    BOOL isVerticalityMirror = self.isVerticalityMirror ? self.isVerticalityMirror() : NO;
    BOOL isHorizontalMirror = self.isHorizontalMirror ? self.isHorizontalMirror() : NO;
    if (isVerticalityMirror || isHorizontalMirror) {
        self.isCanRecovery = YES;
        return;
    }
    
    CGPoint convertCenter = [self convertPoint:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds)) toView:self.imageView];
    CGPoint imageViewCenter = CGPointMake(CGRectGetMidX(self.imageView.bounds), CGRectGetMidY(self.imageView.bounds));
    BOOL isSameCenter = labs((NSInteger)convertCenter.x - (NSInteger)imageViewCenter.x) <= 1 && labs((NSInteger)convertCenter.y - (NSInteger)imageViewCenter.y) <= 1;
    BOOL isOriginFrame = self.rotationDirection == JPImageresizerVerticalUpDirection && [self __imageresizerFrameIsEqualImageViewFrame];
    self.isCanRecovery = !isOriginFrame || !isSameCenter;
}

#pragma mark - puild method

- (void)updateFrameType:(JPImageresizerFrameType)frameType {
    if (self.frameType == frameType) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.frameType = frameType;
    [CATransaction commit];
}

- (void)setupStrokeColor:(UIColor *)strokeColor
              blurEffect:(UIBlurEffect *)blurEffect
                 bgColor:(UIColor *)bgColor
               maskAlpha:(CGFloat)maskAlpha
                animated:(BOOL)isAnimated {
    void (^animations)(void) = ^{
        self.strokeColor = strokeColor;
        [self.blurView setupIsBlur:self.blurView.isBlur
                        blurEffect:blurEffect
                           bgColor:bgColor
                         maskAlpha:maskAlpha
                       isMaskAlpha:self.blurView.isMaskAlpha
                          duration:0];
        self.superview.layer.backgroundColor = bgColor.CGColor;
    };
    if (isAnimated) {
        [UIView animateWithDuration:_defaultDuration delay:0 options:_animationOption animations:animations completion:nil];
    } else {
        animations();
    }
}

- (void)updateImageOriginFrameWithDuration:(NSTimeInterval)duration {
    self.layer.transform = CATransform3DIdentity;
    [self __updateImageOriginFrameWithDirection:JPImageresizerVerticalUpDirection duration:duration];
}

- (void)startImageresizer {
    self.isPrepareToScale = YES;
    [self __removeTimer];
    [self.blurView setIsBlur:NO duration:_blurDuration];
    [self __hideOrShowGridLines:YES animateDuration:_blurDuration];
}

- (void)endedImageresizer {
    UIEdgeInsets contentInset = [self __scrollViewContentInsetWithAdjustResizeFrame:self.imageresizerFrame];
    self.scrollView.contentInset = contentInset;
    [self __addTimer];
}

- (void)rotationWithDirection:(JPImageresizerRotationDirection)direction rotationDuration:(NSTimeInterval)rotationDuration {
    [self __removeTimer];
    [self __updateRotationDirection:direction];
    [self __adjustImageresizerFrame:[self __adjustResizeFrame] isAdvanceUpdateOffset:YES animateDuration:rotationDuration];
}

- (void)willMirror:(BOOL)animated {
    self.window.userInteractionEnabled = NO;
    if (animated) [self.blurView setIsBlur:NO duration:0];
}

- (void)verticalityMirrorWithDiffX:(CGFloat)diffX {
    CGFloat w = [self __isHorizontalDirection:_rotationDirection] ? self.bounds.size.height : self.bounds.size.width;
    CGFloat x = (_baseContentMaxSize.width - w) * 0.5 + diffX;
    CGRect frame = self.frame;
    frame.origin.x = x;
    self.scrollView.frame = frame;
    self.frame = frame;
}

- (void)horizontalMirrorWithDiffY:(CGFloat)diffY {
    CGFloat h = [self __isHorizontalDirection:_rotationDirection] ? self.bounds.size.width : self.bounds.size.height;
    CGFloat y = (_baseContentMaxSize.height - h) * 0.5 + diffY;
    CGRect frame = self.frame;
    frame.origin.y = y;
    self.scrollView.frame = frame;
    self.frame = frame;
}

- (void)mirrorDone {
    [self.blurView setIsBlur:YES duration:_blurDuration];
    [self __checkIsCanRecovery];
    self.window.userInteractionEnabled = YES;
}

- (void)willRecoveryToRoundResize {
    self.window.userInteractionEnabled = NO;
    [self __removeTimer];
    _isRound = YES;
    _resizeWHScale = 1;
    _isArbitrarily = NO;
    _isToBeArbitrarily = NO;
}

- (void)willRecoveryByResizeWHScale:(CGFloat)resizeWHScale isToBeArbitrarily:(BOOL)isToBeArbitrarily {
    self.window.userInteractionEnabled = NO;
    [self __removeTimer];
    _isRound = NO;
    _resizeWHScale = resizeWHScale;
    _isArbitrarily = resizeWHScale <= 0;
    _isToBeArbitrarily = isToBeArbitrarily;
}

- (void)recoveryWithDuration:(NSTimeInterval)duration {
    [self __updateRotationDirection:JPImageresizerVerticalUpDirection];
    
    CGRect adjustResizeFrame = _isArbitrarily ? [self __baseImageresizerFrame] : [self __adjustResizeFrame];
    
    UIEdgeInsets contentInset = [self __scrollViewContentInsetWithAdjustResizeFrame:adjustResizeFrame];
    
    CGFloat minZoomScale = [self __scrollViewMinZoomScaleWithResizeSize:adjustResizeFrame.size];
    
    CGFloat offsetX = -contentInset.left + (_baseImageW * minZoomScale - adjustResizeFrame.size.width) * 0.5;
    CGFloat offsetY = -contentInset.top + (_baseImageH * minZoomScale - adjustResizeFrame.size.height) * 0.5;
    CGPoint contentOffset = CGPointMake(offsetX, offsetY);
    
    [self __updateImageresizerFrame:adjustResizeFrame animateDuration:duration];
    
    self.scrollView.minimumZoomScale = minZoomScale;
    self.scrollView.zoomScale = minZoomScale;
    self.scrollView.contentInset = contentInset;
    self.scrollView.contentOffset = contentOffset;
}

- (void)recoveryDone {
    [self __adjustImageresizerFrame:[self __adjustResizeFrame] isAdvanceUpdateOffset:YES animateDuration:-1.0];
    self.window.userInteractionEnabled = YES;
}

- (void)imageresizerWithComplete:(void(^)(UIImage *resizeImage))complete compressScale:(CGFloat)compressScale {
    if (!complete) return;
    if (compressScale <= 0) {
        complete(nil);
        return;
    }
    
    /**
     * UIImageOrientationUp --------- default orientation
     * UIImageOrientationDown ----- 180 deg rotation
     * UIImageOrientationLeft -------- 90 deg CCW
     * UIImageOrientationRight ------ 90 deg CW
     */
    UIImageOrientation orientation;
    switch (self.rotationDirection) {
        case JPImageresizerHorizontalLeftDirection:
            orientation = UIImageOrientationLeft;
            break;
        case JPImageresizerVerticalDownDirection:
            orientation = UIImageOrientationDown;
            break;
        case JPImageresizerHorizontalRightDirection:
            orientation = UIImageOrientationRight;
            break;
        default:
            orientation = UIImageOrientationUp;
            break;
    }
    
    BOOL isVerMirror = self.isVerticalityMirror ? self.isVerticalityMirror() : NO;
    BOOL isHorMirror = self.isHorizontalMirror ? self.isHorizontalMirror() : NO;
    if ([self __isHorizontalDirection:_rotationDirection]) {
        BOOL temp = isVerMirror;
        isVerMirror = isHorMirror;
        isHorMirror = temp;
    }
    
    UIImage *image = self.imageView.image;
    
    CGRect imageViewBounds = self.imageView.bounds;
    
    CGSize relativeSize = imageViewBounds.size;
    
    CGRect cropFrame = (self.isCanRecovery || self.resizeWHScale > 0) ? [self convertRect:self.imageresizerFrame toView:self.imageView] : imageViewBounds;
    
    BOOL isRoundClip = _isRound;
    
    __weak typeof(self) wSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(wSelf) sSelf = wSelf;
        if (!sSelf) return;
        UIImage *resultImage = [UIImage jpir_resultImageWithImage:image
                                                        cropFrame:cropFrame
                                                     relativeSize:relativeSize
                                                      isVerMirror:isVerMirror
                                                      isHorMirror:isHorMirror
                                                rotateOrientation:orientation
                                                      isRoundClip:isRoundClip
                                                    compressScale:compressScale];
        dispatch_async(dispatch_get_main_queue(), ^{
            complete(resultImage);
        });
    });
}

- (void)superViewUpdateFrame:(CGRect)superViewFrame contentInsets:(UIEdgeInsets)contentInsets duration:(NSTimeInterval)duration {
    self.superview.userInteractionEnabled = NO;
    [self __removeTimer];
    self.isPrepareToScale = YES;
    
    CGFloat superViewW = superViewFrame.size.width;
    CGFloat superViewH = superViewFrame.size.height;
    CGRect superViewBounds = CGRectMake(0, 0, superViewW, superViewH);
    
    CGFloat contentWidth = superViewW - contentInsets.left - contentInsets.right;
    CGFloat contentHeight = superViewH - contentInsets.top - contentInsets.bottom;
    
    CGFloat viewWH;
    if (superViewH > superViewW) {
        viewWH = superViewH * 2;
    } else {
        viewWH = superViewW * 2;
    }
    CGFloat viewX = (contentWidth - viewWH) * 0.5 + contentInsets.left;
    CGFloat viewY = (contentHeight - viewWH) * 0.5 + contentInsets.top;
    CGRect viewFrame = CGRectMake(viewX, viewY, viewWH, viewWH);
    CGRect viewBounds = CGRectMake(0, 0, viewWH, viewWH);
    
    CGFloat imageWHScale = self.imageView.image.size.width / self.imageView.image.size.height;
    CGFloat imgViewW = contentWidth;
    CGFloat imgViewH = imgViewW / imageWHScale;
    if (imgViewH > contentHeight) {
        imgViewH = contentHeight;
        imgViewW = imgViewH * imageWHScale;
    }
    CGFloat imgViewX = (viewWH - imgViewW) * 0.5;
    CGFloat imgViewY = (viewWH - imgViewH) * 0.5;
    CGRect imageViewBounds = CGRectMake(0, 0, imgViewW, imgViewH);
    
    _baseContentMaxSize = CGSizeMake(contentWidth, contentHeight);
    _baseImageW = imgViewW;
    _baseImageH = imgViewH;
    self.originImageFrame = CGRectMake(imgViewX, imgViewY, imgViewW, imgViewH);
    [self __updateMaxResizeFrameWithDirection:self.rotationDirection];
    contentWidth = self.maxResizeW;
    contentHeight = self.maxResizeH;
    
    CGFloat originImgViewW = self.imageView.bounds.size.width;
    CGFloat originImgViewH = self.imageView.bounds.size.height;
    CGRect originZoomFrame = [self convertRect:self.imageresizerFrame toView:self.imageView];
    
    CGFloat zoomScale;
    CGFloat imageresizerW = contentWidth;
    CGFloat imageresizerH = contentHeight;
    CGFloat imageresizerX = (viewWH - imageresizerW) * 0.5;
    CGFloat imageresizerY = (viewWH - imageresizerH) * 0.5;
    if (originZoomFrame.size.width > originZoomFrame.size.height) {
        zoomScale = originImgViewW / originZoomFrame.size.width;
        imageresizerH = imageresizerW * (originZoomFrame.size.height / originZoomFrame.size.width);
        if (imageresizerH > contentHeight) {
            imageresizerH = contentHeight;
            imageresizerW = imageresizerH * (originZoomFrame.size.width / originZoomFrame.size.height);
            imageresizerX += (contentWidth - imageresizerW) * 0.5;
        } else {
            imageresizerY += (contentHeight - imageresizerH) * 0.5;
        }
        zoomScale = imageresizerW / imgViewW;
        zoomScale = zoomScale * (originImgViewW / originZoomFrame.size.width);
    } else {
        imageresizerW = imageresizerH * (originZoomFrame.size.width / originZoomFrame.size.height);
        if (imageresizerW > contentWidth) {
            imageresizerW = contentWidth;
            imageresizerH = imageresizerW * (originZoomFrame.size.height / originZoomFrame.size.width);
            imageresizerY += (contentHeight - imageresizerH) * 0.5;
        } else {
            imageresizerX += (contentWidth - imageresizerW) * 0.5;
        }
        zoomScale = imageresizerH / imgViewH;
        zoomScale = zoomScale * (originImgViewH / originZoomFrame.size.height);
    }
    
    CGRect imageresizerFrame = CGRectMake(imageresizerX, imageresizerY, imageresizerW, imageresizerH);
    CGFloat minimumZoomScale = [self __scrollViewMinZoomScaleWithResizeSize:imageresizerFrame.size];
    
    CGSize svContentSize = CGSizeMake(imgViewW * zoomScale, imgViewH * zoomScale);
    CGRect imageViewFrame = (CGRect){CGPointZero, svContentSize};
    
    UIEdgeInsets svContentInset = UIEdgeInsetsMake(imageresizerY, imageresizerX, imageresizerY, imageresizerX);
    
    CGFloat offsetX = -imageresizerX + svContentSize.width * (originZoomFrame.origin.x / originImgViewW);
    CGFloat offsetY = -imageresizerY + svContentSize.height * (originZoomFrame.origin.y / originImgViewH);
    CGPoint svContentOffset = CGPointMake(offsetX, offsetY);
    
    void (^updateBlock)(void) = ^{
        self.scrollView.minimumZoomScale = minimumZoomScale;
        self.scrollView.zoomScale = zoomScale;
        self.scrollView.contentInset = svContentInset;
        self.imageView.bounds = imageViewBounds;
        self.imageView.frame = imageViewFrame;
        self.scrollView.contentSize = svContentSize;
        self.scrollView.contentOffset = svContentOffset;
        
        [self __checkIsCanRecovery];
        self.isPrepareToScale = NO;
        self.superview.userInteractionEnabled = YES;
    };
    
    self.superview.bounds = superViewBounds;
    self.superview.frame = superViewFrame;
    self.scrollView.frame = self.frame = viewFrame;
    
    [self __updateImageresizerFrame:imageresizerFrame animateDuration:duration];
    [self __hideOrShowGridLines:NO animateDuration:duration];
    [self.blurView setIsBlur:YES duration:duration];
    
    if (duration > 0) {
        // 屏幕旋转时会自动包裹一层系统的旋转动画中，此时使用系统动画API不能自定义动画时长和动画曲线，需要在此忽略这层嵌套关系。
        [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptionOverrideInheritedDuration | UIViewAnimationOptionOverrideInheritedCurve | UIViewAnimationOptionOverrideInheritedOptions | _animationOption) animations:^{
            self.blurView.frame = self.maskLayer.frame = viewBounds;
            self.scrollView.contentInset = svContentInset;
            self.imageView.frame = imageViewFrame;
            self.scrollView.contentOffset = svContentOffset;
        } completion:^(BOOL finished) {
            updateBlock();
        }];
    } else {
        self.blurView.frame = self.maskLayer.frame = viewBounds;
        updateBlock();
    }
}

#pragma mark - UIPanGestureRecognizer

- (void)__panHandle:(UIPanGestureRecognizer *)panGR {
    switch (panGR.state) {
        case UIGestureRecognizerStateBegan:
        {
            [self startImageresizer];
            break;
        }
        case UIGestureRecognizerStateChanged:
        {
            [self __panChangedHandleWithTranslation:[panGR translationInView:self]];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
        {
            [self endedImageresizer];
            break;
        }
        default:
            break;
    }
    [panGR setTranslation:CGPointZero inView:self];
}

- (void)__panChangedHandleWithTranslation:(CGPoint)translation {
    
    CGFloat x = _imageresizerFrame.origin.x;
    CGFloat y = _imageresizerFrame.origin.y;
    CGFloat w = _imageresizerFrame.size.width;
    CGFloat h = _imageresizerFrame.size.height;
    
    switch (_currDR) {
            
        case JPDR_LeftTop: {
            if (_isArbitrarily) {
                x += translation.x;
                y += translation.y;
                
                if (x < self.maxResizeX) {
                    x = self.maxResizeX;
                }
                
                if (y < self.maxResizeY) {
                    y = self.maxResizeY;
                }
                
                w = _diagonal.x - x;
                h = _diagonal.y - y;
                
                if (w < _minImageWH) {
                    w = _minImageWH;
                    x = _diagonal.x - w;
                }
                
                if (h < _minImageWH) {
                    h = _minImageWH;
                    y = _diagonal.y - h;
                }
            } else {
                x += translation.x;
                w = _diagonal.x - x;
                
                if (translation.x != 0) {
                    CGFloat diff = translation.x / _resizeWHScale;
                    y += diff;
                    h = _diagonal.y - y;
                }
                
                if (x < self.maxResizeX) {
                    x = self.maxResizeX;
                    w = _diagonal.x - x;
                    h = w / _resizeWHScale;
                    y = _diagonal.y - h;
                }
                
                if (y < self.maxResizeY) {
                    y = self.maxResizeY;
                    h = _diagonal.y - y;
                    w = h * _resizeWHScale;
                    x = _diagonal.x - w;
                }
                
                if (w < _minImageWH && h < _minImageWH) {
                    if (_resizeWHScale >= 1) {
                        w = _minImageWH;
                        h = w / _resizeWHScale;
                    } else {
                        h = _minImageWH;
                        w = h * _resizeWHScale;
                    }
                    x = _diagonal.x - w;
                    y = _diagonal.y - h;
                }
            }
            
            break;
        }
            
        case JPDR_LeftBottom: {
            if (_isArbitrarily) {
                x += translation.x;
                h += translation.y;
                
                if (x < self.maxResizeX) {
                    x = self.maxResizeX;
                }
                
                CGFloat maxResizeMaxY = CGRectGetMaxY(self.maxResizeFrame);
                if ((y + h) > maxResizeMaxY) {
                    h = maxResizeMaxY - _diagonal.y;
                }
                
                w = _diagonal.x - x;
                
                if (w < _minImageWH) {
                    w = _minImageWH;
                    x = _diagonal.x - w;
                }
                
                if (h < _minImageWH) {
                    h = _minImageWH;
                }
            } else {
                x += translation.x;
                w = _diagonal.x - x;
                
                if (translation.x != 0) {
                    h = w / _resizeWHScale;
                }
                
                if (x < self.maxResizeX) {
                    x = self.maxResizeX;
                    w = _diagonal.x - x;
                    h = w / _resizeWHScale;
                }
                
                CGFloat maxResizeMaxY = CGRectGetMaxY(self.maxResizeFrame);
                if ((y + h) > maxResizeMaxY) {
                    h = maxResizeMaxY - _diagonal.y;
                    w = h * _resizeWHScale;
                    x = _diagonal.x - w;
                }
                
                if (w < _minImageWH && h < _minImageWH) {
                    if (_resizeWHScale >= 1) {
                        w = _minImageWH;
                        h = w / _resizeWHScale;
                    } else {
                        h = _minImageWH;
                        w = h * _resizeWHScale;
                    }
                    x = _diagonal.x - w;
                    y = _diagonal.y;
                }
            }
            
            break;
        }
            
        case JPDR_RightTop: {
            if (_isArbitrarily) {
                y += translation.y;
                w += translation.x;
                
                if (y < self.maxResizeY) {
                    y = self.maxResizeY;
                }
                
                CGFloat maxResizeMaxX = CGRectGetMaxX(self.maxResizeFrame);
                if ((x + w) > maxResizeMaxX) {
                    w = maxResizeMaxX - _diagonal.x;
                }
                
                h = _diagonal.y - y;
                
                if (w < _minImageWH) {
                    w = _minImageWH;
                }
                
                if (h < _minImageWH) {
                    h = _minImageWH;
                    y = _diagonal.y - h;
                }
            } else {
                w += translation.x;
                
                if (translation.x != 0) {
                    CGFloat diff = translation.x / _resizeWHScale;
                    y -= diff;
                    h = _diagonal.y - y;
                }
                
                if (y < self.maxResizeY) {
                    y = self.maxResizeY;
                    h = _diagonal.y - y;
                    w = h * _resizeWHScale;
                }
                
                CGFloat maxResizeMaxX = CGRectGetMaxX(self.maxResizeFrame);
                if ((x + w) > maxResizeMaxX) {
                    w = maxResizeMaxX - _diagonal.x;
                    h = w / _resizeWHScale;
                    y = _diagonal.y - h;
                }
                
                if (w < _minImageWH && h < _minImageWH) {
                    if (_resizeWHScale >= 1) {
                        w = _minImageWH;
                        h = w / _resizeWHScale;
                    } else {
                        h = _minImageWH;
                        w = h * _resizeWHScale;
                    }
                    x = _diagonal.x;
                    y = _diagonal.y - h;
                }
            }
            
            break;
        }
            
        case JPDR_RightBottom: {
            if (_isArbitrarily) {
                w += translation.x;
                h += translation.y;
                
                CGFloat maxResizeMaxX = CGRectGetMaxX(self.maxResizeFrame);
                if ((x + w) > maxResizeMaxX) {
                    w = maxResizeMaxX - _diagonal.x;
                }
                
                CGFloat maxResizeMaxY = CGRectGetMaxY(self.maxResizeFrame);
                if ((y + h) > maxResizeMaxY) {
                    h = maxResizeMaxY - _diagonal.y;
                }
                
                if (w < _minImageWH) {
                    w = _minImageWH;
                }
                
                if (h < _minImageWH) {
                    h = _minImageWH;
                }
            } else {
                w += translation.x;
                
                if (translation.x != 0) {
                    h = w / _resizeWHScale;
                }
                
                CGFloat maxResizeMaxX = CGRectGetMaxX(self.maxResizeFrame);
                if ((x + w) > maxResizeMaxX) {
                    w = maxResizeMaxX - _diagonal.x;
                    h = w / _resizeWHScale;
                }
                
                CGFloat maxResizeMaxY = CGRectGetMaxY(self.maxResizeFrame);
                if ((y + h) > maxResizeMaxY) {
                    h = maxResizeMaxY - _diagonal.y;
                    w = h * _resizeWHScale;
                }
                
                if (w < _minImageWH && h < _minImageWH) {
                    if (_resizeWHScale >= 1) {
                        w = _minImageWH;
                        h = w / _resizeWHScale;
                    } else {
                        h = _minImageWH;
                        w = h * _resizeWHScale;
                    }
                    x = _diagonal.x;
                    y = _diagonal.y;
                }
            }
            
            break;
        }
            
        case JPDR_LeftMid: {
            if (_isArbitrarily) {
                x += translation.x;
                
                if (x < self.maxResizeX) {
                    x = self.maxResizeX;
                }
                
                w = _diagonal.x - x;
                
                if (w < _minImageWH) {
                    w = _minImageWH;
                    x = _diagonal.x - w;
                }
            } else {
                w -= translation.x;
                h = w / _resizeWHScale;
                
                CGFloat maxResizeMaxW = self.maxResizeW;
                if (w > maxResizeMaxW) {
                    w = maxResizeMaxW;
                    h = w / _resizeWHScale;
                }
                CGFloat maxResizeMaxH = self.maxResizeH;
                if (h > maxResizeMaxH) {
                    h = maxResizeMaxH;
                    w = h * _resizeWHScale;
                }
                if (w < _minImageWH && h < _minImageWH) {
                    if (_resizeWHScale >= 1) {
                        w = _minImageWH;
                        h = w / _resizeWHScale;
                    } else {
                        h = _minImageWH;
                        w = h * _resizeWHScale;
                    }
                }
                
                // x轴方向的对立位置不变，所以由x确定w、h
                x = _diagonal.x - w;
                if (x < self.maxResizeX) {
                    x = self.maxResizeX;
                    w = _diagonal.x - x;
                    h = w / _resizeWHScale;
                }
                
                // 再确定y
                y = _diagonal.y - h * 0.5;
                if (y < self.maxResizeY) {
                    y = self.maxResizeY;
                }
                CGFloat maxResizeMaxY = CGRectGetMaxY(self.maxResizeFrame);
                if ((y + h) > maxResizeMaxY) {
                    y = maxResizeMaxY - h;
                }
            }
            break;
        }
            
        case JPDR_RightMid: {
            if (_isArbitrarily) {
                w += translation.x;
                
                CGFloat maxResizeMaxX = CGRectGetMaxX(self.maxResizeFrame);
                if ((x + w) > maxResizeMaxX) {
                    w = maxResizeMaxX - _diagonal.x;
                }
                
                if (w < _minImageWH) {
                    w = _minImageWH;
                }
            } else {
                w += translation.x;
                h = w / _resizeWHScale;
                
                CGFloat maxResizeMaxW = self.maxResizeW;
                if (w > maxResizeMaxW) {
                    w = maxResizeMaxW;
                    h = w / _resizeWHScale;
                }
                CGFloat maxResizeMaxH = self.maxResizeH;
                if (h > maxResizeMaxH) {
                    h = maxResizeMaxH;
                    w = h * _resizeWHScale;
                }
                if (w < _minImageWH && h < _minImageWH) {
                    if (_resizeWHScale >= 1) {
                        w = _minImageWH;
                        h = w / _resizeWHScale;
                    } else {
                        h = _minImageWH;
                        w = h * _resizeWHScale;
                    }
                }
                
                // x轴方向的对立位置不变，所以由x确定w、h
                x = _diagonal.x;
                CGFloat maxResizeMaxX = CGRectGetMaxX(self.maxResizeFrame);
                if ((x + w) > maxResizeMaxX) {
                    w = maxResizeMaxX - x;
                    h = w / _resizeWHScale;
                }
                
                // 再确定y
                y = _diagonal.y - h * 0.5;
                if (y < self.maxResizeY) {
                    y = self.maxResizeY;
                }
                CGFloat maxResizeMaxY = CGRectGetMaxY(self.maxResizeFrame);
                if ((y + h) > maxResizeMaxY) {
                    y = maxResizeMaxY - h;
                }
            }
            break;
        }
            
        case JPDR_TopMid: {
            if (_isArbitrarily) {
                y += translation.y;
                
                if (y < self.maxResizeY) {
                    y = self.maxResizeY;
                }
                
                h = _diagonal.y - y;
                
                if (h < _minImageWH) {
                    h = _minImageWH;
                    y = _diagonal.y - h;
                }
            } else {
                h -= translation.y;
                w = h * _resizeWHScale;
                
                CGFloat maxResizeMaxW = self.maxResizeW;
                if (w > maxResizeMaxW) {
                    w = maxResizeMaxW;
                    h = w / _resizeWHScale;
                }
                CGFloat maxResizeMaxH = self.maxResizeH;
                if (h > maxResizeMaxH) {
                    h = maxResizeMaxH;
                    w = h * _resizeWHScale;
                }
                if (w < _minImageWH && h < _minImageWH) {
                    if (_resizeWHScale >= 1) {
                        w = _minImageWH;
                        h = w / _resizeWHScale;
                    } else {
                        h = _minImageWH;
                        w = h * _resizeWHScale;
                    }
                }
                
                // y轴方向的对立位置不变，所以由y确定w、h
                y = _diagonal.y - h;
                if (y < self.maxResizeY) {
                    y = self.maxResizeY;
                    h = _diagonal.y - y;
                    w = h * _resizeWHScale;
                }
                
                // 再确定x
                x = _diagonal.x - w * 0.5;
                CGFloat maxResizeMaxX = CGRectGetMaxX(self.maxResizeFrame);
                if ((x + w) > maxResizeMaxX) {
                    x = maxResizeMaxX - w;
                }
                if (x < self.maxResizeX) {
                    x = self.maxResizeX;
                }
            }
            break;
        }
            
        case JPDR_BottomMid: {
            if (_isArbitrarily) {
                h += translation.y;
                
                CGFloat maxResizeMaxY = CGRectGetMaxY(self.maxResizeFrame);
                if ((y + h) > maxResizeMaxY) {
                    h = maxResizeMaxY - _diagonal.y;
                }
                
                if (h < _minImageWH) {
                    h = _minImageWH;
                }
            } else {
                h += translation.y;
                w = h * _resizeWHScale;
                
                CGFloat maxResizeMaxW = self.maxResizeW;
                if (w > maxResizeMaxW) {
                    w = maxResizeMaxW;
                    h = w / _resizeWHScale;
                }
                CGFloat maxResizeMaxH = self.maxResizeH;
                if (h > maxResizeMaxH) {
                    h = maxResizeMaxH;
                    w = h * _resizeWHScale;
                }
                if (w < _minImageWH && h < _minImageWH) {
                    if (_resizeWHScale >= 1) {
                        w = _minImageWH;
                        h = w / _resizeWHScale;
                    } else {
                        h = _minImageWH;
                        w = h * _resizeWHScale;
                    }
                }
                
                // y轴方向的对立位置不变，所以由y确定w、h
                y = _diagonal.y;
                CGFloat maxResizeMaxY = CGRectGetMaxY(self.maxResizeFrame);
                if ((y + h) > maxResizeMaxY) {
                    h = maxResizeMaxY - y;
                    w = h * _resizeWHScale;
                }
                
                // 再确定x
                x = _diagonal.x - w * 0.5;
                CGFloat maxResizeMaxX = CGRectGetMaxX(self.maxResizeFrame);
                if ((x + w) > maxResizeMaxX) {
                    x = maxResizeMaxX - w;
                }
                if (x < self.maxResizeX) {
                    x = self.maxResizeX;
                }
            }
            break;
        }
            
        default:
            break;
    }
    
    CGRect imageresizerFrame = CGRectMake(x, y, w, h);
    
    CGFloat zoomScale = self.scrollView.zoomScale;
    CGFloat wZoomScale = 0;
    CGFloat hZoomScale = 0;
    if (w > _startResizeW) {
        wZoomScale = w / _baseImageW;
    }
    if (h > _startResizeH) {
        hZoomScale = h / _baseImageH;
    }
    CGFloat maxZoomScale = MAX(wZoomScale, hZoomScale);
    if (maxZoomScale > zoomScale) {
        zoomScale = maxZoomScale;
    }
    if (zoomScale != self.scrollView.zoomScale) {
        [self.scrollView setZoomScale:zoomScale animated:NO];
    }
    
    CGPoint contentOffset = self.scrollView.contentOffset;
    CGSize contentSize = self.scrollView.contentSize;
    CGRect convertFrame = [self convertRect:imageresizerFrame toView:self.scrollView];
    if (convertFrame.origin.x < 0) {
        contentOffset.x -= convertFrame.origin.x;
    } else if (CGRectGetMaxX(convertFrame) > contentSize.width) {
        contentOffset.x -= CGRectGetMaxX(convertFrame) - contentSize.width;
    }
    if (convertFrame.origin.y < 0) {
        contentOffset.y -= convertFrame.origin.y;
    } else if (CGRectGetMaxY(convertFrame) > contentSize.height) {
        contentOffset.y -= CGRectGetMaxY(convertFrame) - contentSize.height;
    }
    if (!CGPointEqualToPoint(contentOffset, self.scrollView.contentOffset)) {
        [self.scrollView setContentOffset:contentOffset animated:NO];
    }
    
    self.imageresizerFrame = imageresizerFrame;
}

#pragma mark - super method

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    _currDR = JPDR_Center;
    
    if (!_panGR.enabled) {
        return NO;
    }
    
    CGRect frame = _imageresizerFrame;
    CGFloat scopeWH = _scopeWH;
    CGFloat halfScopeWH = _halfScopeWH;
    
    if (_edgeLineIsEnabled &&
        (!CGRectContainsPoint(CGRectInset(frame, -halfScopeWH, -halfScopeWH), point) ||
         CGRectContainsPoint(CGRectInset(frame, halfScopeWH, halfScopeWH), point))) {
        return NO;
    }
    
    CGFloat x = frame.origin.x;
    CGFloat y = frame.origin.y;
    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;
    CGFloat maxX = CGRectGetMaxX(frame);
    CGFloat maxY = CGRectGetMaxY(frame);
    
    CGRect leftTopRect = CGRectMake(x - halfScopeWH, y - halfScopeWH, scopeWH, scopeWH);
    CGRect leftBotRect = CGRectMake(x - halfScopeWH, maxY - halfScopeWH, scopeWH, scopeWH);
    CGRect rightTopRect = CGRectMake(maxX - halfScopeWH, y - halfScopeWH, scopeWH, scopeWH);
    CGRect rightBotRect = CGRectMake(maxX - halfScopeWH, maxY - halfScopeWH, scopeWH, scopeWH);
    
    if (!_isRound) {
        if (CGRectContainsPoint(leftTopRect, point)) {
            _currDR = JPDR_LeftTop;
            _diagonal = CGPointMake(maxX, maxY);
        } else if (CGRectContainsPoint(leftBotRect, point)) {
            _currDR = JPDR_LeftBottom;
            _diagonal = CGPointMake(maxX, y);
        } else if (CGRectContainsPoint(rightTopRect, point)) {
            _currDR = JPDR_RightTop;
            _diagonal = CGPointMake(x, maxY);
        } else if (CGRectContainsPoint(rightBotRect, point)) {
            _currDR = JPDR_RightBottom;
            _diagonal = CGPointMake(x, y);
        }
    }
    
    if (_currDR == JPDR_Center) {
        CGRect leftMidRect = CGRectNull;
        CGRect rightMidRect = CGRectNull;
        CGRect topMidRect = CGRectNull;
        CGRect botMidRect = CGRectNull;
        CGFloat midX = CGRectGetMidX(frame);
        CGFloat midY = CGRectGetMidY(frame);
        
        if (_edgeLineIsEnabled && !_isRound) {
            leftMidRect = CGRectMake(x - halfScopeWH, y + halfScopeWH, scopeWH, h - scopeWH);
            rightMidRect = CGRectMake(maxX - halfScopeWH, y + halfScopeWH, scopeWH, h - scopeWH);
            topMidRect = CGRectMake(x + halfScopeWH, y - halfScopeWH, w - scopeWH, scopeWH);
            botMidRect = CGRectMake(x + halfScopeWH, maxY - halfScopeWH, w - scopeWH, scopeWH);
        } else if (_isShowMidDots || _isRound) {
            leftMidRect = CGRectMake(x - halfScopeWH, midY - halfScopeWH, scopeWH, scopeWH);
            rightMidRect = CGRectMake(maxX - halfScopeWH, midY - halfScopeWH, scopeWH, scopeWH);
            topMidRect = CGRectMake(midX - halfScopeWH, y - halfScopeWH, scopeWH, scopeWH);
            botMidRect = CGRectMake(midX - halfScopeWH, maxY - halfScopeWH, scopeWH, scopeWH);
        }
        
        if (CGRectContainsPoint(leftMidRect, point)) {
            _currDR = JPDR_LeftMid;
            _diagonal = CGPointMake(maxX, midY);
        } else if (CGRectContainsPoint(rightMidRect, point)) {
            _currDR = JPDR_RightMid;
            _diagonal = CGPointMake(x, midY);
        } else if (CGRectContainsPoint(topMidRect, point)) {
            _currDR = JPDR_TopMid;
            _diagonal = CGPointMake(midX, maxY);
        } else if (CGRectContainsPoint(botMidRect, point)) {
            _currDR = JPDR_BottomMid;
            _diagonal = CGPointMake(midX, y);
        } else {
            return NO;
        }
    }
    
    _startResizeW = w;
    _startResizeH = h;
    return YES;
}

@end
