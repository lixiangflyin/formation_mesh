//
//  MSHRendererViewController.h
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>

//用来表示解析的各个阶段
typedef enum MSHRendererViewControllerStatus
{
    MSHRendererViewControllerStatusUnknown,
    MSHRendererViewControllerStatusFileLoadParsingVertices,
    MSHRendererViewControllerStatusFileLoadParsingVertexNormals,
    MSHRendererViewControllerStatusFileLoadParsingFaces,
    MSHRendererViewControllerStatusMeshCalibrating,
    MSHRendererViewControllerStatusMeshLoadingIntoGraphicsHardware,
    MSHRendererViewControllerStatusMeshDisplaying,
} MSHRendererViewControllerStatus;

@class MSHRendererViewController;
@protocol MSHRendererViewControllerDelegate <NSObject>

- (void)rendererChangedStatus:(MSHRendererViewControllerStatus)newStatus;
- (void)rendererEncounteredError:(NSError *)error;

//显示触发点
- (void)showTouchPoint:(CGPoint)touch withX:(float)x withY:(float)y withZ:(float)z;

@end

//继承于glkview
@interface MSHRendererViewController : GLKViewController <MSHRendererViewControllerDelegate>

- (id)initWithDelegate:(id<MSHRendererViewControllerDelegate>)rendererDelegate;
- (void)loadFile:(NSURL *)fileURL;

@property (nonatomic, weak) id<MSHRendererViewControllerDelegate>rendererDelegate;
@property (nonatomic, strong) UIColor *meshColor;
@property (nonatomic, assign) float inertiaDampeningRate;

//我添加的变量
@property (nonatomic, assign) BOOL isShowVertex;

@end
