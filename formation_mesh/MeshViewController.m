//
//  MeshViewController.m
//  formation_mesh
//
//  Created by apple on 14-3-28.
//  Copyright (c) 2014年 apple. All rights reserved.
//

#import "MeshViewController.h"
#import "UIView+ZXQuartz.h"
#import "JSONKit.h"

@interface MeshViewController ()

@end

@implementation MeshViewController

-(void)dealloc
{
    [_controlImageView release];
    [_locationLabel release];
    [_HUD release];
    [super dealloc];
}

-(id)init
{
    self = [super init];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = [NSString stringWithFormat:@"三维检测测试系统"];
    _isShowControlPoint = NO;
    
    UIBarButtonItem *rightBtn = [[UIBarButtonItem alloc]initWithTitle:@"命令" style:UIBarButtonItemStylePlain target:self action:@selector(showCommandView)];
    self.navigationItem.rightBarButtonItem = rightBtn;
    [rightBtn release];
    
    _locationLabel = [[UILabel alloc]init];
    [_locationLabel setTextColor:[UIColor blackColor]];
    [_locationLabel setTextAlignment:NSTextAlignmentLeft];
    _locationLabel.numberOfLines = 3;
    _locationLabel.lineBreakMode = NSLineBreakByCharWrapping;
    //_locationLabel.backgroundColor = [UIColor blackColor];
    [self.view addSubview:_locationLabel];
    
    _controlImageView = [[UIImageView alloc]init];
    _controlImageView.backgroundColor = [UIColor redColor];
    [self.view addSubview:_controlImageView];
    
    [self loadModel:@"chair1"];
}

-(void)showCommandView
{
    NSLog(@"command!");
    
    if (_commandView == nil) {
        _commandView = [[CommandView alloc]initWithDelegate:self];
    }
    
    [self.view addSubview:_commandView];
}

#pragma -mark CommandButtonDelegate
-(void)clickButtonValue:(int)btnNumber
{
    //发送请求
    NSLog(@"you choose %d!",btnNumber);
    
    NSString *strUrl = [NSString stringWithFormat:@"http://121.21.2.1.php?%d",btnNumber];
    
    NSURL *url = [NSURL URLWithString:@"http://bbs.seu.edu.cn/api/hot/boards.json"];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
    NSData *received = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    NSString *str = [[NSString alloc]initWithData:received encoding:NSUTF8StringEncoding];
    NSDictionary *dic = [str objectFromJSONString];
    NSLog(@"%@",dic);
    
    //下载文件
    //[self loadFile:url];
    
}

//通过地址下载ply文件
- (void)loadFile:(NSURL *)urlToLoad
{
    _HUD = [[MBProgressHUD alloc] initWithView:self.view];
	_HUD.labelText = @"正在下载解析...";
    [self.view addSubview:_HUD];
    [_HUD show:YES];
    
    //下载完成，拷贝到本地，前提消去之前拷贝文件
    [NSURLConnection sendAsynchronousRequest:[[NSURLRequest alloc] initWithURL:urlToLoad]
                                       queue:[[NSOperationQueue alloc] init]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error)
     {
         //表示没有错误
         NSAssert(!error && data, @"Error downloading!");
         //取文件
         NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
         NSString *documentPath = [searchPaths objectAtIndex:0];
         NSString *currentFile = [documentPath stringByAppendingPathComponent:@"current_model.obj"];
         //文件处理，删除操作
         NSFileManager *fm = [NSFileManager defaultManager];
         //先删除旧版本
         [fm removeItemAtPath:currentFile error:nil];
         NSAssert([data writeToFile:currentFile atomically:YES], @"Couldn't write to the current_model file.");
         dispatch_async(dispatch_get_main_queue(), ^
                        {
                            //super 将本地文件进行解析处理，解析过程是点解析，三角解析之后再显示出来
                            [super loadFile:[NSURL fileURLWithPath:currentFile]];
                        });
     }];
}

//本地载入ply文件
-(void)loadModel:(NSString *)model
{
    //self.title = [NSString stringWithFormat:@"%@模型",_modelName];
    
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }

    _HUD = [[MBProgressHUD alloc] initWithView:self.view];
	_HUD.labelText = @"正在解析...";
    [self.view addSubview:_HUD];
    [_HUD show:YES];
    //NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    //NSString *documentPath = [searchPaths objectAtIndex:0];
    //NSString *currentFile = [documentPath stringByAppendingPathComponent:@"4.obj"];
    
    NSString *currentFile = [[NSBundle mainBundle] pathForResource:model ofType:@"obj"];
    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       //super 将本地文件进行解析处理，解析过程是点解析，三角解析之后再显示出来
                       [super loadFile:[NSURL fileURLWithPath:currentFile]];
                   });
    
}

- (IBAction)setRenderMode:(id)sender {
    
    UISegmentedControl *segControl = (UISegmentedControl*)sender;
    NSInteger selectedSeg = segControl.selectedSegmentIndex;
    switch (selectedSeg)
    {
        case 0:
            //NSLog(@"Points");
            self.isShowVertex = YES;
            break;
        case 1:
            //NSLog(@"face");
            self.isShowVertex  = NO;
            break;
        default:
            break;
    }
}

- (IBAction)showControlPoint:(id)sender {
    
    if (_isShowControlPoint) {
        
        _controlImageView.hidden = YES;
        _locationLabel.hidden = YES;
        _isShowControlPoint = NO;
        [(UIBarButtonItem *)sender setTitle:@"显示控制点"];
    }
    else{
        _controlImageView.hidden = NO;
        _locationLabel.hidden = NO;
        _isShowControlPoint = YES;
        [(UIBarButtonItem *)sender setTitle:@"不显示控制点"];
    }
}

- (void)showTouchPoint:(CGPoint)touch withX:(float)x withY:(float)y withZ:(float)z
{
    NSLog(@"%f %f %f %f %f",touch.x,touch.y,x,y,z);
    //CGContextFillRect(self.context, CGRectMake(355,355,1,1));
    
    if (_isShowControlPoint) {
        
        [_controlImageView setFrame:CGRectMake(touch.x, touch.y, 8, 8)];
        
        NSString *loaction = [NSString stringWithFormat:@"   x: %f\n   y: %f\n   z :%f",x,y,z];
        [_locationLabel setText:loaction];
        [_locationLabel setFrame:CGRectMake(touch.x, touch.y, 150, 65)];
    }
    
}

#pragma mark - MSHRendererViewControllerDelegate
//解析过程中，缓冲条显示顺序
- (void)rendererChangedStatus:(MSHRendererViewControllerStatus)newStatus
{
    NSString *loaderHeaderText = nil;
    NSString *loaderInfoText = @"";
    switch (newStatus)
    {
        case MSHRendererViewControllerStatusFileLoadParsingVertices:
            loaderHeaderText = @"Loading File";
            loaderInfoText = @"parsing vertices...";
            break;
        case MSHRendererViewControllerStatusFileLoadParsingVertexNormals:
            loaderHeaderText = @"Loading File";
            loaderInfoText = @"parsing vertex normals...";
            break;
        case MSHRendererViewControllerStatusFileLoadParsingFaces:
            loaderHeaderText = @"Loading File";
            loaderInfoText = @"parsing faces...";
            break;
        case MSHRendererViewControllerStatusMeshCalibrating:
            loaderHeaderText = @"Loading File";
            loaderInfoText = @"calibrating the mesh...";
            break;
        case MSHRendererViewControllerStatusMeshLoadingIntoGraphicsHardware:
            loaderHeaderText = @"Loading File";
            loaderInfoText = @"loading into the gpu...";
            break;
        default:
            loaderInfoText = nil;
            break;
    }
    //非空就进行显示操作
    if (loaderInfoText.length > 0 || loaderHeaderText.length > 0)
    {
        NSLog(@"正在解析！");
    }
    else
    {
        //隐藏显示条
        [_HUD removeFromSuperview];
    }
}

//错误回调函数
- (void)rendererEncounteredError:(NSError *)error
{
    UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"错误" message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK!" otherButtonTitles:nil, nil];
    [alert show];
    [alert release];
    double delayInSeconds = 2.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void)
                   {
                       [_HUD removeFromSuperview];
                       //[self showModelSelectionTableAnimated:YES];
                   });
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    barButtonItem.title = NSLocalizedString(@"模型", @"模型");
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    // Called when the view is shown again in the split view, invalidating the button and popover controller.
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    self.masterPopoverController = nil;
}

- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    return YES;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
