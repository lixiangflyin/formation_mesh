//
//  InfoView.m
//  formation_mesh
//
//  Created by apple on 14-3-31.
//  Copyright (c) 2014年 apple. All rights reserved.
//

#import "InfoView.h"

@implementation InfoView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        
        _objNameLabel = [[UILabel alloc]initWithFrame:CGRectMake(10, 30, 70, 80)];
        [_objNameLabel setTextColor:[UIColor blackColor]];
        [_objNameLabel setTextAlignment:NSTextAlignmentLeft];
        _objNameLabel.text = @"文件";
        _objNameLabel.numberOfLines = 1;
        _objNameLabel.lineBreakMode = NSLineBreakByCharWrapping;

        [self addSubview:_objNameLabel];
        
        _controlPointLabel = [[UILabel alloc]initWithFrame:CGRectMake(10, 30, 70, 80)];
        [_controlPointLabel setTextColor:[UIColor blackColor]];
        [_controlPointLabel setTextAlignment:NSTextAlignmentLeft];
        _controlPointLabel.numberOfLines = 3;
        _controlPointLabel.lineBreakMode = NSLineBreakByCharWrapping;
        
        [self addSubview:_controlPointLabel];
    }
    return self;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
