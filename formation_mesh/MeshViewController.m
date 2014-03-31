//
//  MeshViewController.m
//  formation_mesh
//
//  Created by apple on 14-3-28.
//  Copyright (c) 2014年 apple. All rights reserved.
//

#import "MeshViewController.h"
#import "UIView+ZXQuartz.h"

@interface MeshViewController ()

@end

@implementation MeshViewController

-(void)dealloc
{
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
