//
//  MSHRange.h
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#ifndef MishMeshSample_MSHRange_h
#define MishMeshSample_MSHRange_h

#import <OpenGLES/ES2/gl.h>

typedef struct MSHRange //用于显示时，坐标的大小分布
{
    GLfloat min;
    GLfloat max;
} MSHRange;

static inline float readNextNonSpace(NSInputStream *stream, NSInteger *numBytesRead)
{
    uint8_t nonSpace;
    while((*numBytesRead = [stream read:&nonSpace maxLength:1]) > 0 && isspace(nonSpace));
    return nonSpace;
}

static inline void seekToNextLine(NSInputStream *stream)
{
    uint8_t storage;
    NSInteger numBytesRead = 0;
    while((numBytesRead = [stream read:&storage maxLength:1]) > 0 && storage != '\n');
}

static inline void amendRange(MSHRange *range, GLfloat candidate)
{
    if (candidate < range->min)
    {
        range->min = candidate;
    }
    else if (candidate > range->max)
    {
        range->max = candidate;
    }
}

//获取平均值
static inline GLfloat getMidpoint(MSHRange range)
{
    return (range.max + range.min)/2;
}

//获取差值
static inline GLfloat getSpread(MSHRange range)
{
    return range.max - range.min;
}

//初始化，即构造函数
static inline MSHRange makeRange(GLfloat min, GLfloat max)
{
    MSHRange range = {min, max};
    return range;
}

//极限范围
static inline MSHRange makeExtremeRange()
{
    return makeRange(FLT_MAX, -FLT_MAX);
}


#endif
