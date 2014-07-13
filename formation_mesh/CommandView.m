//
//  CommandView.m
//  formation_mesh
//
//  Created by apple on 14-6-6.
//  Copyright (c) 2014年 apple. All rights reserved.
//

#import "CommandView.h"

@implementation CommandView

- (id)initWithDelegate:(id)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        //self.backgroundColor = [UIColor blackColor];
        self.frame = CGRectMake(0, 64, 768, 1024-44-64);
        self.backgroundColor = [UIColor clearColor];
        NSLog(@"frame: %f",self.frame.size.width);
        
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        UIButton *backgroundBtn = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, 768, 1024)];
        backgroundBtn.backgroundColor = [UIColor lightGrayColor];
        backgroundBtn.alpha = 0.5;
        [backgroundBtn addTarget:self action:@selector(hideTheView:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:backgroundBtn];
        [backgroundBtn release];
        
        UIView *view = [[UIView alloc]initWithFrame:CGRectMake(508, 0, 260, 368)];
        view.backgroundColor = [UIColor whiteColor];
        [self addSubview:view];
        [view release];
        
        UILabel *label = [[UILabel alloc]initWithFrame:CGRectMake(508+59, 20, 142, 26)];
        label.text =@"人脸变形指令";
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor redColor];
        [self addSubview:label];
        [label release];
        
        NSArray *btnWords = [[NSArray alloc]initWithObjects:@"原始模型", @"鼻子放大", @"耳朵放大", @"下颚变大", @"眼睛变大", @"上颚变大", nil];
        
        for (int i = 0; i < 6; i++) {
            UIButton *btn = [[UIButton alloc]init];
            btn.frame = CGRectMake(508+59, 72+50*i, 142, 27);
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [btn setTitle:btnWords[i] forState:UIControlStateNormal];
            [btn setBackgroundColor:[UIColor blueColor]];
            [btn addTarget:self action:@selector(chooseCommand:) forControlEvents:UIControlEventTouchUpInside];
            [btn setTag:200+i];
            [self addSubview:btn];
            [btn release];
        }
        
    }
    return self;
}

//去除view
-(void)hideTheView:(id)sender
{
    [self removeFromSuperview];
}

//请求情况
- (void)chooseCommand:(id)sender
{
    UIButton *but =(UIButton *)sender;
    
    [_delegate clickButtonValue:(int)but.tag-200];
    
    [self removeFromSuperview];
}

@end
