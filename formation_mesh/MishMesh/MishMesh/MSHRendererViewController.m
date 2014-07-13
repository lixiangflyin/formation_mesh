//
//  MSHRendererViewController.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MSHRendererViewController.h"
#import "MSHFile.h"
#import "MSHVertex.h"
#import "MSHFace.h"
#import <CoreMotion/CoreMotion.h>
#import "MSHDeviceMotionIconView.h"
#import <fenv.h>

#define BUFFER_OFFSET(i)                                        ((char *)NULL + (i))
#define CAM_VERT_ANGLE                                          GLKMathDegreesToRadians(65)
#define PORTION_OF_DIMENSION_TO_FIT                             1.2f
#define RATIO_OF_NEAR_Z_BOUND_LOCATION_TO_EYE_Z_LOCATION        0.8f
#define ROTATION_DECELERATION_RATE                              0.1f
#define MAX_SCALE                                               (4*M_PI)
#define MIN_SCALE                                               1
#define DOUBLE_TAP_CHECK_TIMEOUT                                0.1f
#define ANIMATION_LENGTH                                        0.5f

#define DEVICE_MOTION_UPDATE_INTERVAL                           0.3f
#define DIMENSION_OF_DEVICE_MOTION_ICON                         40.0f
#define BOUNCE_FACTOR                                           1.2f
#define DEVICE_MOTION_ICON_PADDING                              5.0f
#define DEVICE_MOTION_ICON_RESTING_X                            self.view.bounds.size.width - DIMENSION_OF_DEVICE_MOTION_ICON - DEVICE_MOTION_ICON_PADDING
#define DEVICE_MOTION_ICON_RESTING_Y                            DEVICE_MOTION_ICON_PADDING
#define DEVICE_MOTION_ANIMATION_LENGTH                          0.2f
#define FINGER_FAT                                              22.0f

#define PINCH_ANCHOR_TOLERANCE                                  2.0f

#define DEFAULT_MESH_COLOR             [UIColor colorWithRed:0.7f green:0.2f blue:0.2f alpha:1.0f]
//#define DEFAULT_MESH_COLOR            [UIColor colorWithRed:0.0f green:1.0f blue:0.0f alpha:1.0f]
//#define DEFAULT_BACKGROUND_COLOR      [UIColor colorWithRed:212.0/255.0 green:209.0/255.0 blue:187.0/255.0 alpha:1.0]
#define DEFAULT_BACKGROUND_COLOR        [UIColor colorWithRed:0.0f green:1.0f blue:0.0f alpha:1.0f]

typedef struct MSHAnimationAttributes
{
    float rateOfChange;
    float targetRateOfChange;
    float changeAcceleration;
    float targetValue;
    bool targetValueNotSignificant;
} MSHAnimationAttributes;

typedef struct MSHEulerAngles    //欧拉角
{
    float yaw;
    float pitch;
    float roll;
} MSHEulerAngles;

typedef struct MSHQuaternionSnapshot
{
    GLKQuaternion quaternion; //四元量
    NSTimeInterval time;     //时间标志
} MSHQuaternionSnapshot;

@interface MSHRendererViewController()
{
    GLuint _vao;   // 搞定
    GLfloat _eyeZ; // For the view matrix 视口矩阵
    //_aspect表示宽高比，三个变量用来创建视口矩阵的--
    GLfloat _aspect, _nearZ, _farZ;
	GLfloat _maxDistanceToFit;   //最大距离 搞定
    //虚拟世界矩阵，变换矩阵（旋转，平移，放大），projection投影矩阵（用来显示的）
    GLKMatrix4 _modelMatrix, _modelTransforms, _viewMatrix;
    GLubyte *_numVerticesInFace; //一个面中顶点数
    GLuint _numFaces;            //面的数量
    
    GLKVector3 _outlierPosition;  //用来作视图坐标中心点
    
    MSHAnimationAttributes _scaleAnimationAttributes;  //各种动作的动画属性
    MSHAnimationAttributes _panXAnimationAttributes;
    MSHAnimationAttributes _panYAnimationAttributes;
    MSHAnimationAttributes _pitchAnimationAttributes;
    MSHAnimationAttributes _yawAnimationAttributes;
    MSHAnimationAttributes _rollAnimationAttributes;
    MSHAnimationAttributes _quaternionAnimationAttributes;
    MSHAnimationAttributes _quaternionInertialAnimationAttributes;
    MSHEulerAngles _animatingEulerAngles;  //欧拉角对象
    
    CGPoint _quaternionAnchorPoint;       //开始旋转初始点坐标
    GLKQuaternion _currentRotationQuaternion;  //当前每一次旋转（变动）的四元数参量
    GLKQuaternion _totalQuaternion;    //总的旋转四元数参量
    MSHQuaternionSnapshot _currentQuaternionSnapshot;  //纪录前一次时间下旋转四元量
    float _angleRateOfChangeDueToDrag;  //拖动角度变化
    GLKVector3 _inertialQuaternionAxis;   //四元数的坐标点
    
    CGPoint _panAnchorPoint;    //平移手势点的位置
    GLKVector3 _totalPan;       //平移总量，3*1向量

    CGPoint _lastSignificantScreenPinchAnchor;  //捏合，放大缩小上一次点的位置
    GLKVector3 _pinchWorldAnchorPoint;   //转化为世界坐标系中的位置
    GLfloat _scale, _currentScale;     //放大倍数，当前放大倍数
}

@property (strong, nonatomic) EAGLContext *context;         //opengl环境
@property (strong, nonatomic) GLKBaseEffect *effect;        //着色器
@property (strong, nonatomic) CMMotionManager *motionManager; //管理运动相关的类，包括加速度计，陀螺仪和电子罗盘（定位）
@property (strong, nonatomic) CMAttitude *referenceAttitude; //封装了当前设备在空间中的姿态信息三维attitude,相当于一个四元数。包括三个角，存在于coreMotion    参考位置
@property (strong, nonatomic) MSHDeviceMotionIconView *deviceMotionIconView;
@property (strong, nonatomic) UIPanGestureRecognizer *panGestureRecognizer;
@property (strong, nonatomic) UIPanGestureRecognizer *rotationGestureRecognizer;

@end

@implementation MSHRendererViewController

#pragma mark - UIViewController

- (id)init
{
    return [self initWithDelegate:self];
}

- (id)initWithDelegate:(id<MSHRendererViewControllerDelegate>)rendererDelegate
{
    if (self = [super init])
    {
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.rendererDelegate = self;
    self.meshColor = DEFAULT_MESH_COLOR;   //渲染颜色
    self.inertiaDampeningRate = 2;
    _isShowVertex = NO;
   
    //设置opengl环境上下文，当其他代码改变了全局上下文的情况下，这件事相当重要。只能渲染三角形，无法渲染方形
    //初始化版本opengl2.0
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    GLKView *view = (GLKView *)self.view;
    self.view.opaque = YES;
    self.view.backgroundColor = DEFAULT_BACKGROUND_COLOR;
    view.context = self.context;   
    view.drawableDepthFormat = GLKViewDrawableDepthFormat16;
    view.drawableMultisample = GLKViewDrawableMultisample4X;
    view.multipleTouchEnabled = YES;
    
    //设置当前的context
    [EAGLContext setCurrentContext:self.context];
    //辅助类，实现一些通用的着色器，着色器不同于glsl着色器
    self.effect = [[GLKBaseEffect alloc] init];
    //设置使能
    self.effect.light0.enabled = GL_TRUE;
    
    CGFloat colorComponents[4];
    //取土豪金各颜色
    getRGBA(self.meshColor, colorComponents);  //得到colorComponents颜色
    self.effect.light0.diffuseColor = GLKVector4Make(colorComponents[0], colorComponents[1], colorComponents[2], colorComponents[3]);
    
    //打开深度缓存区
    glEnable(GL_DEPTH_TEST);
    //创建控制三维信息的控制器，core motion
    self.motionManager = [[CMMotionManager alloc] init];
    [self.motionManager startDeviceMotionUpdates];
    
    //缩放手势，识别手指捏合
    [self.view addGestureRecognizer:setUpGestureRecognizer([[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)])];
    //长按手势
    UILongPressGestureRecognizer *longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    setUpGestureRecognizer(longPressRecognizer);
    longPressRecognizer.cancelsTouchesInView = YES;
    [self.view addGestureRecognizer:longPressRecognizer];
    //平移手势，识别手指拖动手势
    self.panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.panGestureRecognizer.minimumNumberOfTouches = 2;
    [self.view addGestureRecognizer:setUpGestureRecognizer(self.panGestureRecognizer)];
    //翻转
    self.rotationGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.rotationGestureRecognizer.maximumNumberOfTouches = 1;
    [self.view addGestureRecognizer:setUpGestureRecognizer(self.rotationGestureRecognizer)];
}

- (BOOL)shouldAutorotate
{
    return self.referenceAttitude == nil;
}

- (void)dealloc
{
    [self tearDownOpenGL];
    [self cleanupDisplayedMesh];
}

//内存警告函数
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    if ([self isViewLoaded] && ([[self view] window] == nil))
    {
        self.view = nil;
        [self tearDownOpenGL];
        self.context = nil;
    }
}

//销毁eaglContext和effect，索引缓冲区释放了吗，还有顶点缓冲区
- (void)tearDownOpenGL
{
    [EAGLContext setCurrentContext:nil];
    self.effect = nil;
}


- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    if (UIInterfaceOrientationIsLandscape(fromInterfaceOrientation) ^
        UIInterfaceOrientationIsLandscape(self.interfaceOrientation))
    {
        //设置视口参数以及返回原来视图状态
        [self calculateCameraParams];
        [self animateToInitialPerspective];
    }
}

#pragma mark - File Loading
//释放内存
- (void)cleanupDisplayedMesh
{
    _vao = 0;
    //c释放法
    free(_numVerticesInFace);
    _numVerticesInFace = NULL;
    //平移，旋转初始化
    _totalQuaternion = GLKQuaternionMake(0, 0, 0, 1);
    _currentRotationQuaternion = GLKQuaternionMake(0, 0, 0, 1);
    _totalPan = GLKVector3Make(0, 0, 0);
    //放大倍数都置为1
    _scale = 1;
    _currentScale = 1;
}

//用来解析obj文件以及显示三维模型
- (void)loadFile:(NSURL *)fileURL
{
    ASSERT_MAIN_THREAD();
    [self cleanupDisplayedMesh];
    NSAssert([fileURL isFileURL], @"loadFile: only operates on local file URLs.");
    MSHFile *file = [[MSHFile alloc] initWithURL:fileURL];
    __weak MSHRendererViewController *weakSelf = self;
    [file parseWithStatusUpdateBlock:^(MSHFile *parsedFile)
     {
         ASSERT_MAIN_THREAD();
         switch (parsedFile.status)
         {
             case MSHFileStatusFailure:
                 [weakSelf.rendererDelegate rendererEncounteredError:parsedFile.processingError];
                 break;
             case MSHFileStatusReady:
                 [weakSelf loadFileIntoGraphicsHardware:file];
                 break;
             case MSHFileStatusCalibrating:
                 [weakSelf.rendererDelegate rendererChangedStatus:MSHRendererViewControllerStatusMeshCalibrating];
                 break;
             case MSHFileStatusParsingVertices:
                 [weakSelf.rendererDelegate rendererChangedStatus:MSHRendererViewControllerStatusFileLoadParsingVertices];
                 break;
             case MSHFileStatusParsingFaces:
                 [weakSelf.rendererDelegate rendererChangedStatus:MSHRendererViewControllerStatusFileLoadParsingVertexNormals];
                 break;
             case MSHFileStatusParsingVertexNormals:
                 [weakSelf.rendererDelegate rendererChangedStatus:MSHRendererViewControllerStatusFileLoadParsingFaces];
                 break;
             default:
                 [weakSelf.rendererDelegate rendererChangedStatus:MSHRendererViewControllerStatusUnknown];
                 break;
         }
     }];
}

//设置projectionMatrix投影矩阵的相关参数
- (void)calculateCameraParams
{
    _aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
    GLfloat camHorizAngle = 2*atan(_aspect*tan(CAM_VERT_ANGLE/2));
    GLfloat distanceToFitHorizontally = (_maxDistanceToFit * PORTION_OF_DIMENSION_TO_FIT)/(2*tan(camHorizAngle/2));
    GLfloat distanceToFitVertically = (_maxDistanceToFit * PORTION_OF_DIMENSION_TO_FIT)/(2*tan(CAM_VERT_ANGLE/2));
    GLfloat distanceToFitDepthWise = (_maxDistanceToFit/2 * PORTION_OF_DIMENSION_TO_FIT);
    GLfloat nearZLocation = MAX(distanceToFitDepthWise, MAX(distanceToFitHorizontally, distanceToFitVertically));
    _eyeZ = nearZLocation/RATIO_OF_NEAR_Z_BOUND_LOCATION_TO_EYE_Z_LOCATION;
    _nearZ = _eyeZ - nearZLocation;
    _farZ = _nearZ + 2*nearZLocation;
    
}

//将数据拷贝到gpu中去，准备好渲染工作
- (void)loadFileIntoGraphicsHardware:(MSHFile *)file
{
    //提示语句
    [self rendererChangedStatus:MSHRendererViewControllerStatusMeshLoadingIntoGraphicsHardware];
    
    //获取最大空间最大距离
    _maxDistanceToFit = [file.outlierVertex distanceToVertex:[MSHVertex vertexWithX:getMidpoint(file.xRange) y:getMidpoint(file.yRange) z:getMidpoint(file.zRange)]]*2;
    //创建projection投影矩阵参数
    [self calculateCameraParams];
    
    //物体坐标系转到世界坐标系。获取初始模型矩阵，translation平移的意思
    _modelMatrix = GLKMatrix4MakeTranslation(-getMidpoint(file.xRange), -getMidpoint(file.yRange), -getMidpoint(file.zRange));
    _numVerticesInFace = file.numVerticesInFace;
    _numFaces = file.numFaces;
    
    //起始点，用于标定初始位置。貌似没起作用
    _outlierPosition = file.outlierVertex.position;
    
    //使用VertexArray加载顶点 法线数据，委托函数glview需要这个量
    glGenVertexArraysOES(1, &_vao);
    glBindVertexArrayOES(_vao);
    
    //创建一个新的顶点缓冲区对象，初始化缓冲区
    GLuint arrayVbo;
    glGenBuffers(1, &arrayVbo);
    glBindBuffer(GL_ARRAY_BUFFER, arrayVbo);
    glBufferData(GL_ARRAY_BUFFER, file.vertexCoordinatesSize, file.vertexCoordinates, GL_STATIC_DRAW);
    
    //创建一个新的索引缓冲区对象，到时候将其数据转到gpu中
    GLuint elementsVbo;
    glGenBuffers(1, &elementsVbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, elementsVbo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, file.vertexIndicesSize, file.vertexIndices, GL_STATIC_DRAW);
    
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    //glkvertexattribposition顶点属性指针类型：顶点坐标
    //3 一个顶点坐标有几个值来表示x，y，z
    //GL_FLOAT 每个数值的数据类型
    //直接使用24并不优雅，24 ＝ sizeof（GLfloat）*6: 到下一个顶点坐标数据的步长
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, 24, BUFFER_OFFSET(0));
    glEnableVertexAttribArray(GLKVertexAttribNormal);
    //直接使用12并不优雅，12 ＝ sizeof（GLfloat）*3
    glVertexAttribPointer(GLKVertexAttribNormal, 3, GL_FLOAT, GL_FALSE, 24, BUFFER_OFFSET(12));
    //要求格式
    glBindVertexArrayOES(0);
    
    //正式显示三维模型
    [self rendererChangedStatus:MSHRendererViewControllerStatusMeshDisplaying];
}

#pragma mark - Handling User Input
//每次手势操作，都将其初始化
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    // Cancel animations 单位化属性变量，全部参数置0
    memset(&_scaleAnimationAttributes, 0, sizeof(_scaleAnimationAttributes));
    memset(&_panXAnimationAttributes, 0, sizeof(_panXAnimationAttributes));
    memset(&_panYAnimationAttributes, 0, sizeof(_panYAnimationAttributes));
    memset(&_pitchAnimationAttributes, 0, sizeof(_pitchAnimationAttributes));
    memset(&_yawAnimationAttributes, 0, sizeof(_yawAnimationAttributes));
    memset(&_rollAnimationAttributes, 0, sizeof(_rollAnimationAttributes));
    memset(&_quaternionAnimationAttributes, 0, sizeof(_quaternionAnimationAttributes));
    memset(&_quaternionInertialAnimationAttributes, 0, sizeof(_quaternionAnimationAttributes));
    
    //回调显示点的结果
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch  locationInView:self.view];
    
    GLKVector3 touchPoint = mapTouchToSphere(self.view.bounds.size, point);
    //回调
    [_rendererDelegate showTouchPoint:point withX:touchPoint.v[0] withY:touchPoint.v[1] withZ:touchPoint.v[2]];
}

//手指捏合，手势放大缩小
- (void)handlePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer
{
    //获得除去旋转后变换总变化（平移＋缩放），GLKMatrix4Invert求逆
    GLKMatrix4 transformsExceptRotation = GLKMatrix4Multiply(_modelTransforms, GLKMatrix4Invert([self totalRotationMatrix], NULL));
    //获得最终矩阵，    “视图变换*模型变换”
    GLKMatrix4 modelviewMatrix = GLKMatrix4Multiply(_viewMatrix, GLKMatrix4Multiply(transformsExceptRotation, _modelMatrix));
    if ([pinchGestureRecognizer state] == UIGestureRecognizerStateBegan)
    {
        //捏合的最后点位置
        _lastSignificantScreenPinchAnchor = [pinchGestureRecognizer locationInView:self.view];
        //捏合点转换为世界坐标中
        _pinchWorldAnchorPoint = screenToWorld(_lastSignificantScreenPinchAnchor, self.view.bounds.size,
                                         self.effect, modelviewMatrix);
    }
    if ([pinchGestureRecognizer state] == UIGestureRecognizerStateBegan ||
        [pinchGestureRecognizer state] == UIGestureRecognizerStateChanged)
    {
        //计算当前视图空间下放大的倍数，捏合完后_currentScale ＝ 1
        _currentScale = MIN(MAX_SCALE/_scale, MAX(MIN_SCALE/_scale, pinchGestureRecognizer.scale));
        
        if (pinchGestureRecognizer.numberOfTouches == 2)
        {
            //捏合后的点位置
            CGPoint newScreenAnchorPoint = [pinchGestureRecognizer locationInView:self.view];
            //计算捏合前后的距离
            CGFloat distanceToLastSignificantAnchor = getDistance(newScreenAnchorPoint, _lastSignificantScreenPinchAnchor);
            //当当前倍数大于1或捏合距离大于2
            if (_currentScale > 1.0f || distanceToLastSignificantAnchor > PINCH_ANCHOR_TOLERANCE)
            {
                //新的世界坐标系定位点
                GLKVector3 newWorldAnchorPoint = screenToWorld(newScreenAnchorPoint, self.view.bounds.size, self.effect, modelviewMatrix);
                //不为空
                if (!isnan(newWorldAnchorPoint.x) && !isnan(newWorldAnchorPoint.y) && !isnan(newWorldAnchorPoint.z))
                {
                    //_lastSignificantScreenPinchAnchor置新值
                    _lastSignificantScreenPinchAnchor = newScreenAnchorPoint;
                    //计算差值
                    GLKVector3 additionalPan = GLKVector3Make(_pinchWorldAnchorPoint.x - newWorldAnchorPoint.x,
                                                              _pinchWorldAnchorPoint.y - newWorldAnchorPoint.y,
                                                              0);
                    //顺带计算平移总量
                    _totalPan = GLKVector3Add(_totalPan, additionalPan);
                }
            }
        }
    }
    else if (pinchGestureRecognizer.state == UIGestureRecognizerStateEnded ||
             pinchGestureRecognizer.state == UIGestureRecognizerStateCancelled)
    {
        //计算放大倍数
        _scale = MIN(MAX_SCALE, MAX(MIN_SCALE, _currentScale*_scale));
        //将当前放大倍数置为1
        _currentScale = 1;
    }
}

//计算两点间距离
static inline CGFloat getDistance(CGPoint point1, CGPoint point2)
{
    CGFloat dx = point1.x - point2.x;
    CGFloat dy = point1.y - point2.y;
    return sqrtf(dx*dx + dy*dy);
}

//长按手势函数
- (void)handleLongPress:(UILongPressGestureRecognizer *)longPressRecognizer
{
    if ([longPressRecognizer state] == UIGestureRecognizerStateBegan)
    {
        //管理器如果有变化，则执行器函数体
        if (self.motionManager.deviceMotion.attitude && UIInterfaceOrientationIsPortrait(self.interfaceOrientation))
        {
            //移除管理器
            [self.deviceMotionIconView removeFromSuperview];
            self.deviceMotionIconView = nil;
            //定义新的管理器
            self.deviceMotionIconView = [[MSHDeviceMotionIconView alloc] init];
            //长按点位置
            CGPoint touchLocation = [longPressRecognizer locationInView:self.view];
            //管理器的位置
            self.deviceMotionIconView.frame = CGRectMake(touchLocation.x, touchLocation.y, 0, 0);
            [self.view addSubview:self.deviceMotionIconView];
            //界面动画函数
            [UIView animateWithDuration:DEVICE_MOTION_ANIMATION_LENGTH*BOUNCE_FACTOR animations:^
             {
                 CGFloat dimension = DIMENSION_OF_DEVICE_MOTION_ICON*BOUNCE_FACTOR;
                 self.deviceMotionIconView.frame = CGRectMake(self.deviceMotionIconView.frame.origin.x - dimension/2,
                                                              self.deviceMotionIconView.frame.origin.y - dimension - FINGER_FAT, dimension, dimension);
             } completion:^(BOOL finished)
             {
                 [UIView animateWithDuration:DEVICE_MOTION_ANIMATION_LENGTH/2 animations:^
                  {
                      //这个不清楚啦
                      self.deviceMotionIconView.bounds = CGRectMake(0, 0,
                                                                    DIMENSION_OF_DEVICE_MOTION_ICON,
                                                                    DIMENSION_OF_DEVICE_MOTION_ICON);
                  }];
             }];
        }
    }
    else if ([longPressRecognizer state] == UIGestureRecognizerStateEnded && UIInterfaceOrientationIsPortrait(self.interfaceOrientation))
    {
        //长按结束
        self.referenceAttitude = self.motionManager.deviceMotion.attitude;
        //界面执行动作
        [UIView animateWithDuration:ANIMATION_LENGTH animations:^
        {
            self.deviceMotionIconView.bounds = CGRectMake(0, 0, DIMENSION_OF_DEVICE_MOTION_ICON, DIMENSION_OF_DEVICE_MOTION_ICON);
             self.deviceMotionIconView.frame = CGRectMake(DEVICE_MOTION_ICON_RESTING_X, DEVICE_MOTION_ICON_RESTING_Y,
                                                          DIMENSION_OF_DEVICE_MOTION_ICON, DIMENSION_OF_DEVICE_MOTION_ICON);
        }];
        self.deviceMotionIconView.frame = CGRectMake(DEVICE_MOTION_ICON_RESTING_X, DEVICE_MOTION_ICON_RESTING_Y,
                                                     DIMENSION_OF_DEVICE_MOTION_ICON, DIMENSION_OF_DEVICE_MOTION_ICON);
    }
}

//手指拖动手势,即平移
- (void)handlePan:(UIPanGestureRecognizer *)panRecognizer
{
    //检测是否是双指移动
    if (panRecognizer == self.panGestureRecognizer && panRecognizer.numberOfTouches >= 2)
    {
        //开始移动
        if ([panRecognizer state] == UIGestureRecognizerStateBegan)
        {
            //开始移动点
            _panAnchorPoint = [panRecognizer locationInView:self.view];
        }
        //移动过程中
        else if ([panRecognizer state] == UIGestureRecognizerStateChanged)
        {
            //移动后的点
            CGPoint touchPoint = [panRecognizer locationInView:self.view];
            //
            GLKMatrix4 modelviewMatrix = GLKMatrix4Multiply(_viewMatrix, _modelMatrix);
            //移动初始点转化为空间向量
            GLKVector3 panAnchorPoint = screenToWorld(_panAnchorPoint, self.view.bounds.size, self.effect, modelviewMatrix);
            //移动后的点转化为空间向量
            GLKVector3 worldTouchPoint = screenToWorld(touchPoint, self.view.bounds.size, self.effect, modelviewMatrix);
            //前后向量差
            GLKVector3 additionalPan = GLKVector3Make((panAnchorPoint.x - worldTouchPoint.x),
                                                      (panAnchorPoint.y - worldTouchPoint.y),
                                                      (panAnchorPoint.z - worldTouchPoint.z));
            //平移向量累积量计为_totalPan
            _totalPan = GLKVector3Add(_totalPan, additionalPan);
            //赋予_panAnchorPoint新值
            _panAnchorPoint = touchPoint;
        }
    }
    else if (panRecognizer == self.rotationGestureRecognizer)
    {
        //旋转手势开始
        if ([panRecognizer state] == UIGestureRecognizerStateBegan)
        {
            //开始旋转初始点位置
            _quaternionAnchorPoint = [panRecognizer locationOfTouch:0 inView:self.view];
        }
        else if ([panRecognizer state] == UIGestureRecognizerStateChanged)
        {
            // Single finger dragging will trigger rotation.单手指拖动会引起
            //旋转后后手势点位置
            CGPoint currentTouchPoint = [panRecognizer locationOfTouch:0 inView:self.view];
            //旋转后点位置转换为向量
            GLKVector3 currentTouchSphereVector = mapTouchToSphere(self.view.bounds.size, currentTouchPoint);
            //旋转前点位置转换为向量
            GLKVector3 previousTouchSphereVector = mapTouchToSphere(self.view.bounds.size, _quaternionAnchorPoint);
            //每次旋转量变换差 旋转四元量
            _currentRotationQuaternion = getQuaternion(previousTouchSphereVector, currentTouchSphereVector);
            //获取四元量中的角度
            float currentAngle = GLKQuaternionAngle(_currentRotationQuaternion);
            //没发现用途？？？？？
            GLKQuaternion diffQuaternion = GLKQuaternionMultiply(GLKQuaternionMake(-_currentQuaternionSnapshot.quaternion.x,
                                                                                   -_currentQuaternionSnapshot.quaternion.y,
                                                                                   -_currentQuaternionSnapshot.quaternion.z,
                                                                                   _currentQuaternionSnapshot.quaternion.w), _currentRotationQuaternion);
            //当前时间量
            NSDate *now = [NSDate date];
            //拖动角度变化，动画角
            _angleRateOfChangeDueToDrag = GLKQuaternionAngle(diffQuaternion)/([now timeIntervalSince1970] - _currentQuaternionSnapshot.time);
            //获取当前旋转四元量中的坐标
            _inertialQuaternionAxis = GLKQuaternionAxis(_currentRotationQuaternion);
            
            // The axis of rotation is undefined when the quaternion angle becomes M_PI.
            // We'll flush the current quaternion when the angle get to M_PI/2.
            if (currentAngle >= M_PI_2)
            {
                [self flushCurrenQuaternionWithNewAnchorPoint:currentTouchPoint];
            }
            //设置snaphot
            _currentQuaternionSnapshot = MSHQuaternionSnapshotMake(_currentRotationQuaternion);
        }
        else if ([panRecognizer state] == UIGestureRecognizerStateEnded ||
                 [panRecognizer state] == UIGestureRecognizerStateCancelled)
        {
            //平移结束 重设相关量
            [self flushCurrenQuaternionWithNewAnchorPoint:CGPointMake(0, 0)];
            //动画属性
            _quaternionInertialAnimationAttributes = MSHAnimationAttributesMakeInertial(_angleRateOfChangeDueToDrag, self.inertiaDampeningRate);
        }
    }
}

- (void)flushCurrenQuaternionWithNewAnchorPoint:(CGPoint)newAnchorPoint
{
    //叠加旋转量
    _totalQuaternion = GLKQuaternionMultiply(_currentRotationQuaternion, _totalQuaternion);
    //当前旋转四元量置为单位向量
    _currentRotationQuaternion = GLKQuaternionMake(0, 0, 0, 1);
    //当前平移点位置
    _quaternionAnchorPoint = newAnchorPoint;
}

//手势触摸屏幕结束后
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    //获取各种欧拉值
    if (self.referenceAttitude)
    {
        CMAttitude *attitude = self.motionManager.deviceMotion.attitude;
        [attitude multiplyByInverseOfAttitude:self.referenceAttitude];
        //获取欧拉角度变化
        _animatingEulerAngles.pitch = attitude.pitch;
        _animatingEulerAngles.yaw = attitude.yaw;
        _animatingEulerAngles.roll = attitude.roll;
        //各种动作的属性设置，比如捏合，旋转等等
        _pitchAnimationAttributes = MSHAnimationAttributesMake(_animatingEulerAngles.pitch, 0, ANIMATION_LENGTH);
        _yawAnimationAttributes = MSHAnimationAttributesMake(_animatingEulerAngles.yaw, 0, ANIMATION_LENGTH);
        _rollAnimationAttributes = MSHAnimationAttributesMake(_animatingEulerAngles.roll, 0, ANIMATION_LENGTH);
        self.referenceAttitude = nil;
        //界面动画伴随的动作
        [UIView animateWithDuration:DEVICE_MOTION_ANIMATION_LENGTH animations:^
         {
             self.deviceMotionIconView.frame = CGRectMake(self.deviceMotionIconView.center.x, self.deviceMotionIconView.center.y, 0, 0);
         } completion:^(BOOL finished)
         {
             [self.deviceMotionIconView removeFromSuperview];
             self.deviceMotionIconView = nil;
         }];
    }
    if (touch.tapCount == 2)
    {
        //返回初始位置
        [self animateToInitialPerspective];
    }
    
    //回调显示点的结果
    CGPoint point = [touch  locationInView:self.view];
    
    GLKVector3 touchPoint = mapTouchToSphere(self.view.bounds.size, point);
    //回调
    [_rendererDelegate showTouchPoint:point withX:touchPoint.v[0] withY:touchPoint.v[1] withZ:touchPoint.v[2]];
}

//屏幕点到世界坐标系中的转换
static inline GLKVector3 screenToWorld(CGPoint screenPoint, CGSize screenSize, GLKBaseEffect *effect, GLKMatrix4 modelviewMatrix)
{
    screenPoint.y = screenSize.height - screenPoint.y;
    GLint viewport[4];
    viewport[0] = 0;
    viewport[1] = 0;
    viewport[2] = screenSize.width;
    viewport[3] = screenSize.height;
    
    GLKVector3 worldZero = GLKMathProject(GLKVector3Make(0.0f, 0.0f, 0.0f),
                                          modelviewMatrix,
                                          effect.transform.projectionMatrix,
                                          viewport);
    bool success;
    GLKVector3 vector = GLKMathUnproject(GLKVector3Make(screenPoint.x, screenPoint.y, worldZero.z),
                                         modelviewMatrix,
                                         effect.transform.projectionMatrix,
                                         viewport,
                                         &success);
    if (!success)
    {
        vector = GLKVector3Make(nan(""), nan(""), nan(""));
    }
    
    return vector;
}

#pragma mark - Animation
//返回初始状态
- (void)animateToInitialPerspective
{
    //放大动画属性
    _scaleAnimationAttributes = MSHAnimationAttributesMake(_scale, 1.0f, ANIMATION_LENGTH);
    //平移动画属性
    _panXAnimationAttributes = MSHAnimationAttributesMake(_totalPan.x, 0.0f, ANIMATION_LENGTH);
    _panYAnimationAttributes = MSHAnimationAttributesMake(_totalPan.y, 0.0f, ANIMATION_LENGTH);
    float quaternionAngle = GLKQuaternionAngle(_totalQuaternion);
    //旋转动画属性
    _quaternionAnimationAttributes = MSHAnimationAttributesMake(quaternionAngle, 0.0f, ANIMATION_LENGTH);
}

//初始化属性，包括多种变量
static inline MSHAnimationAttributes MSHAnimationAttributesMake(float startValue, float endValue, float animationLength)
{
    MSHAnimationAttributes animationAttributes;
    float diff = endValue - startValue;
    animationAttributes.targetRateOfChange = (diff*2)/animationLength;
    animationAttributes.rateOfChange = 0;
    animationAttributes.changeAcceleration = animationAttributes.targetRateOfChange/(animationLength/2);
    animationAttributes.targetValue = endValue;
    animationAttributes.targetValueNotSignificant = NO;
    return animationAttributes;
}

static inline MSHAnimationAttributes MSHAnimationAttributesMakeInertial(float currentRateOfChange, float inertiaDampeningRate)
{
    MSHAnimationAttributes animationAttributes;
    animationAttributes.targetRateOfChange = 0;
    animationAttributes.rateOfChange = currentRateOfChange;
    animationAttributes.changeAcceleration = -(currentRateOfChange/currentRateOfChange)*currentRateOfChange*inertiaDampeningRate;
    animationAttributes.targetValueNotSignificant = YES;
    return animationAttributes;
}

//返回
static inline BOOL MSHAnimationAttributesAreIntertial(MSHAnimationAttributes animationAttributes)
{
    return animationAttributes.targetValueNotSignificant;
}

//
static inline BOOL applyAnimationAttributes(float *attribute, MSHAnimationAttributes *animationAttributes, NSTimeInterval timeSinceLastUpdate)
{
    BOOL animationDone = NO;
    if (fabsf((*animationAttributes).targetRateOfChange - (*animationAttributes).rateOfChange) > fabsf(timeSinceLastUpdate*(*animationAttributes).changeAcceleration) &&
        ((*animationAttributes).targetValueNotSignificant || fabsf(*attribute - (*animationAttributes).targetValue) > fabsf(timeSinceLastUpdate*(*animationAttributes).rateOfChange)))
    {
        (*animationAttributes).rateOfChange += timeSinceLastUpdate*(*animationAttributes).changeAcceleration;
    }
    else if ((*animationAttributes).targetRateOfChange)
    {
        (*animationAttributes).rateOfChange = (*animationAttributes).targetRateOfChange;
        (*animationAttributes).targetRateOfChange = 0;
        (*animationAttributes).changeAcceleration = -(*animationAttributes).changeAcceleration;
        
    }
    else if ((*animationAttributes).changeAcceleration)
    {
        if (!(*animationAttributes).targetValueNotSignificant) *attribute = (*animationAttributes).targetValue;
        animationDone = YES;
        memset(animationAttributes, 0, sizeof(*animationAttributes));
    }
    else
    {
        animationDone = YES;
    }
    
    *attribute += timeSinceLastUpdate*(*animationAttributes).rateOfChange;
    
    return animationDone;
}

#pragma mark - OpenGL drawing
//更新数据，它是delegate方法用来更新数据的，不做UI更新，这部分涉及到很头痛的矩阵变幻，
//暂时不去分析它的算法把
- (void)update
{
    //获取总旋转四元数
    GLKQuaternion preinertialQuaternion = [self preinertialQuaternion];
    //上次更新时间赋给timeSinceLastUpdate
    float timeSinceLastUpdate = self.timeSinceLastUpdate;
    //获取旋转四元数（旋转轴＋角度）中的角度
    float oldQuaternionAngle = GLKQuaternionAngle(preinertialQuaternion);
    //定义新角度
    float newQuaternionAngle = oldQuaternionAngle;
    //角度作调整，动画属性作变化
    applyAnimationAttributes(&newQuaternionAngle, &_quaternionAnimationAttributes, timeSinceLastUpdate);
    //定义四元数
    preinertialQuaternion = GLKQuaternionMakeWithAngleAndVector3Axis(newQuaternionAngle, GLKQuaternionAxis(preinertialQuaternion));
    if (oldQuaternionAngle != newQuaternionAngle)
    {
        //调整总旋转量
        _totalQuaternion = preinertialQuaternion;
    }
    float inertialAngle = 0;
    //计算惯性角及动画属性？？？
    applyAnimationAttributes(&inertialAngle, &_quaternionInertialAnimationAttributes, timeSinceLastUpdate);
    GLKQuaternion finalQuaternion;
    if (inertialAngle)
    {
        if (inertialAngle >= 2*M_PI)
        {
            inertialAngle -= 2*M_PI;
        }
        //最终总旋转四元数，联合旋转
        //GLKQuaternionMakeWithAngleAndVector3Axis:创建一个坐标轴或旋转角度的quaternion
        //inertialQuaternionAxis来自于旋转手势中每次旋转的旋转直线
        _totalQuaternion = GLKQuaternionMultiply(GLKQuaternionMakeWithAngleAndVector3Axis(inertialAngle, _inertialQuaternionAxis), _totalQuaternion);
        finalQuaternion = _totalQuaternion;
    }
    else
    {
        //否则就不变
        finalQuaternion = preinertialQuaternion;
    }
    //涉及到平移、旋转、放大三大矩阵
    _modelTransforms = GLKMatrix4Multiply(GLKMatrix4MakeTranslation(-_totalPan.x, -_totalPan.y, -_totalPan.z),
                                          GLKMatrix4Multiply(GLKMatrix4MakeScale(_scale*_currentScale, _scale*_currentScale, _scale*_currentScale),
                                                             GLKMatrix4MakeWithQuaternion(finalQuaternion)));
    //然后乘以初始矩阵modelMatrix
    GLKMatrix4 transformedModelMatrix = GLKMatrix4Multiply(_modelTransforms, _modelMatrix);
    //视图矩阵，从哪里看即_eyeZ
    GLKMatrix4 viewMatrix = GLKMatrix4MakeLookAt(0, 0, _eyeZ,
                                                 0, 0, 0,
                                                 0.0f, 1.0f, 0.0f);
    //修正viewMatrix矩阵
    if (self.referenceAttitude)
    {
        // The accelerometer is controlling the view matrix
        //加速表控制视图变换矩阵
        CMAttitude *attitude = self.motionManager.deviceMotion.attitude;
        [attitude multiplyByInverseOfAttitude:self.referenceAttitude];
        
        viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(attitude.yaw, 0.0f, 0.0f, -1.0f), viewMatrix);
        viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(attitude.roll, 0.0f, -1.0f, 0.0f), viewMatrix);
        viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(attitude.pitch, -1.0f, 0.0f, 0.0f), viewMatrix);
    }
    //触发屏幕就会改变欧拉角
    else if (_animatingEulerAngles.pitch || _animatingEulerAngles.yaw || _animatingEulerAngles.roll)
    {
        // We are animating back to the initial pitch and yaw (0, 0)
        applyAnimationAttributes(&_animatingEulerAngles.pitch, &_pitchAnimationAttributes, timeSinceLastUpdate);
        applyAnimationAttributes(&_animatingEulerAngles.yaw, &_yawAnimationAttributes, timeSinceLastUpdate);
        applyAnimationAttributes(&_animatingEulerAngles.roll, &_rollAnimationAttributes, timeSinceLastUpdate);
        //viewMatrix是最终视图变换矩阵
        if (_animatingEulerAngles.yaw)
            viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(_animatingEulerAngles.yaw, 0.0f, 0.0f, -1.0f), viewMatrix);
        if (_animatingEulerAngles.roll)
            viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(_animatingEulerAngles.roll, 0.0f, -1.0f, 0.0f), viewMatrix);
        if (_animatingEulerAngles.pitch)
            viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(_animatingEulerAngles.pitch, -1.0f, 0.0f, 0.0f), viewMatrix);
    }
    _viewMatrix = viewMatrix;
    //对于GLKBaseEffect着色器，下面的代码用来更新矩阵
    //而对于可编程着色器，这有所不同
    self.effect.transform.modelviewMatrix = GLKMatrix4Multiply(_viewMatrix, transformedModelMatrix);
    //三个变量用来创建投影矩阵的
    self.effect.transform.projectionMatrix = GLKMatrix4MakePerspective(CAM_VERT_ANGLE, _aspect, _nearZ, _farZ);
    
    applyAnimationAttributes(&_scale, &_scaleAnimationAttributes, timeSinceLastUpdate);
    applyAnimationAttributes(&_totalPan.x, &_panXAnimationAttributes, timeSinceLastUpdate);
    applyAnimationAttributes(&_totalPan.y, &_panYAnimationAttributes, timeSinceLastUpdate);
}

//委托delegate方法，是用来将变化后的三维模型显示在屏幕上，要知道它自动触发，时时刻刻每桢都触发
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    CGFloat colorComponents[4];
    // Could optimize this by caching the color components for the background color.
    //可以优化这个显示背景颜色，获取colorComponents
    getRGBA(self.view.backgroundColor, colorComponents);
    glClearColor(colorComponents[0], colorComponents[1], colorComponents[2], colorComponents[3]);
    //GL_DEPTH_BUFFER_BIT与前面glEnable（GL_DEPTH_TEST）对应
    //清除操作
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    if (_vao)
    {
        //指定Draw使用的顶点数组
        glBindVertexArrayOES(_vao);
        //prepareToDraw，绑定着色器到当前的OpenGL EScontext
        [self.effect prepareToDraw];
        
        
        
        GLushort *faceOffset = 0;
        for (int i = 0; i < _numFaces; i++)
        {
            if (_isShowVertex) {
                glPointSize(1.0);
                //glDrawElements(GL_POINTS, _numVerticesInFace[i], GL_UNSIGNED_SHORT, (const void *)faceOffset);
                glDrawElements(GL_LINE_LOOP, _numVerticesInFace[i], GL_UNSIGNED_SHORT, (const void *)faceOffset);
            }
            else{
                glDrawElements(GL_TRIANGLE_FAN, _numVerticesInFace[i], GL_UNSIGNED_SHORT, (const void *)faceOffset);
            }
       
            faceOffset += _numVerticesInFace[i];
        }
    }
}

#pragma mark - Quaternion Rotation Helpers
//获得最终旋转矩阵
- (GLKMatrix4)totalRotationMatrix
{
    return GLKMatrix4MakeWithQuaternion([self preinertialQuaternion]);
}

//获取最终旋转四元数，与上面性质基本相同
- (GLKQuaternion)preinertialQuaternion
{
    //_currentRotationQuaternion每次旋转后都归为单位化
    return GLKQuaternionMultiply(_currentRotationQuaternion, _totalQuaternion);
}

//把点转化为球面上的点。矩阵变换，即获得旋转矩阵？？？
static inline GLKVector3 mapTouchToSphere(CGSize viewSize, CGPoint touchCoordinates)
{
    CGFloat sphereRadius = MIN(viewSize.width, viewSize.height)/2.0f;
    GLKVector3 xyCenter = GLKVector3Make(viewSize.width/2, viewSize.height/2, 0);
    GLKVector3 touchVectorFromCenter = GLKVector3Subtract(GLKVector3Make(touchCoordinates.x, touchCoordinates.y, 0), xyCenter);
    touchVectorFromCenter = GLKVector3Make(touchVectorFromCenter.x, -touchVectorFromCenter.y, touchVectorFromCenter.z);
    
    GLfloat radiusSquared = sphereRadius*sphereRadius;
    GLfloat xyLengthSquared = touchVectorFromCenter.x*touchVectorFromCenter.x + touchVectorFromCenter.y*touchVectorFromCenter.y;
    
    // Pythagoras has entered the building
    if (radiusSquared >= xyLengthSquared)
        touchVectorFromCenter.z = sqrt(radiusSquared - xyLengthSquared);
    else
    {
        touchVectorFromCenter.x *= radiusSquared/sqrt(xyLengthSquared);
        touchVectorFromCenter.y *= radiusSquared/sqrt(xyLengthSquared);
        touchVectorFromCenter.z = 0;
    }
    return GLKVector3Normalize(touchVectorFromCenter);
}

//计算两向量差，即转化为四元量，用于旋转量计算
static inline GLKQuaternion getQuaternion(GLKVector3 unitVector1, GLKVector3 unitVector2)
{
    //旋转轴向量
    GLKVector3 axis = GLKVector3CrossProduct(unitVector1, unitVector2);
    //旋转角度
    GLfloat angle = acosf(GLKVector3DotProduct(unitVector1, unitVector2));
    GLKQuaternion result = GLKQuaternionMakeWithAngleAndVector3Axis(angle, axis);
    if (result.w != 1)
        //标准化？？？
        result = GLKQuaternionNormalize(result);
    return result;
}

//好像是纪录上一次的状态
static inline MSHQuaternionSnapshot MSHQuaternionSnapshotMake(GLKQuaternion q)
{
    MSHQuaternionSnapshot snapshot;
    snapshot.quaternion = q;
    snapshot.time = [[NSDate date] timeIntervalSince1970];
    return snapshot;
}

//打印出四元数矩阵
static inline void printQuaternion(GLKQuaternion quaternion)
{
    GLKVector3 axis = GLKQuaternionAxis(quaternion);
    float angle = GLKQuaternionAngle(quaternion);
    VLog(@"(%f, %f, %f) %f", axis.x, axis.y, axis.z, angle);
}

#pragma mark - Misc. Helpers
//设置着色器colorComponents颜色
static inline void getRGBA(UIColor *color, CGFloat *colorComponents)
{
    //返回颜色
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(color.CGColor);
    //返回颜色空间模式
    CGColorSpaceModel colorSpaceModel = CGColorSpaceGetModel(colorSpace);
    
    switch (colorSpaceModel)
    {
        //rgb格式
        case kCGColorSpaceModelRGB:
            [color getRed:&colorComponents[0] green:&colorComponents[1] blue:&colorComponents[2] alpha:&colorComponents[3]];
            break;
        case kCGColorSpaceModelMonochrome:
        {
            CGFloat white;
            [color getWhite:&white alpha:&colorComponents[3]];
            colorComponents[0] = white;
            colorComponents[1] = white;
            colorComponents[2] = white;
        }
            break;
        default:
            NSCAssert(NO, @"Unsupported color space: %d", colorSpaceModel);
            break;
    }
}

static inline UIGestureRecognizer *setUpGestureRecognizer(UIGestureRecognizer *recognizer)
{
    //手势的
    recognizer.delaysTouchesBegan = NO;
    //手势
    recognizer.cancelsTouchesInView = NO;
    return recognizer;
}


#pragma mark - MSHRendererViewControllerDelegate

- (void)rendererChangedStatus:(MSHRendererViewControllerStatus)newStatus
{
    
}

- (void)rendererEncounteredError:(NSError *)error
{
    
}

- (void)showTouchPoint:(CGPoint)touch withX:(float)x withY:(float)y withZ:(float)z
{
}

@end

