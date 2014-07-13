//
//  CommandView.h
//  formation_mesh
//
//  Created by apple on 14-6-6.
//  Copyright (c) 2014年 apple. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol CommandButtonDelegate <NSObject>

-(void)clickButtonValue:(int)btnNumber;

@end

@interface CommandView : UIView

@property (nonatomic, assign) id delegate;

- (id)initWithDelegate:(id)delegate;

@end
