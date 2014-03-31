//
//  FileViewController.h
//  formation_mesh
//
//  Created by apple on 14-3-28.
//  Copyright (c) 2014年 apple. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MeshViewController.h"

@interface FileViewController : UITableViewController

@property (nonatomic, retain) MeshViewController *meshViewController;
@property (nonatomic, retain) NSMutableArray *meshFiles;;

@end
