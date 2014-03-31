//
//  MeshViewController.h
//  formation_mesh
//
//  Created by apple on 14-3-28.
//  Copyright (c) 2014年 apple. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MBProgressHUD.h"
#import "MishMesh/MSHRendererViewController.h"

@interface MeshViewController :  MSHRendererViewController

@property (strong, nonatomic) UIPopoverController *masterPopoverController;
 
@property (strong,nonatomic) MBProgressHUD *HUD;

@property (strong, nonatomic) UILabel *locationLabel;

@property (strong, nonatomic) UIImageView *controlImageView;

@property (strong,nonatomic) NSString *modelName;

@property (nonatomic) BOOL isShowControlPoint;

-(void) loadModel:(NSString *)model;

- (IBAction)setRenderMode:(id)sender;
- (IBAction)showControlPoint:(id)sender;

@end
