//
//  MSHObjParser.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MSHObjParser.h"
#import "MSHVertex.h"
#import "MSHFace.h"
#import "MSHParser_InternallyWritableProperties.h"

#define DISK_IO_CHUNK_SIZE      1<<17
//#define DISK_IO_CHUNK_SIZE      1<<17

@implementation MSHObjParser

- (id)initWithFileURL:(NSURL *)fileURL
{
    if (self = [super init])
    {
        self.fileURL = fileURL;
        self.parserStage = MSHParsingStageUnknown;
    }
    return self;
}

- (void)parseFileWithStatusChangeBlock:(void (^)(MSHParser *parser))statusChangeUpdate
{
    //确保有文件
    NSAssert(self.fileURL && statusChangeUpdate, @"Did not submit enough to the parser.");
    //更新状态变量
    self.onStatusUpdateBlock = statusChangeUpdate;
    // Don't want to use a weak version of self in the block below. Need self to stick around until the block's executed.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
    {
        //初始化 MSHRange：存储了最大值最小值
        MSHRange outXRange = makeExtremeRange();
        MSHRange outYRange = makeExtremeRange();
        MSHRange outZRange = makeExtremeRange();
        NSMutableArray *faces = [NSMutableArray array];    //内存自动分配释放
        NSMutableArray *vertices = [NSMutableArray array];
        NSMutableArray *tmpVertices = [[NSMutableArray alloc] init]; //中间变量
        NSMutableArray *tmpNormals = [[NSMutableArray alloc] init];
        
        //错误标志
        NSError *error = nil;
        size_t chunkSize = DISK_IO_CHUNK_SIZE;     //打开的最大容量64K，读取长度
        //打开一个文件准备读取
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:self.fileURL error:&error];
        if (!fileHandle || error)
        {
            //打不开路径文件
            self.parseError = error;
            self.parserStage = MSHParsingStageError;  //解析状态变量
            return;
        }

        NSString *partialLine = @"";
        NSData *fileData = nil;   //文件数据流
        //每次读取了64k 为了设置了一个循环利用缓冲区载文件之间传输数据，提高效率
        do
        {
            @autoreleasepool
            {
                fileData = [fileHandle readDataOfLength:chunkSize];
                NSString *ingestedString = [[NSString alloc] initWithBytes:fileData.bytes length:fileData.length encoding:NSUTF8StringEncoding];
                //分割字符串
                NSMutableArray *ingestedLines = [NSMutableArray arrayWithArray:[ingestedString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]];
                ingestedString = nil;
                [ingestedLines replaceObjectAtIndex:0 withObject:[partialLine stringByAppendingString:[ingestedLines objectAtIndex:0]]];
                //文件字符串长度大于64K
                if (fileData.length >= chunkSize)
                {
                    //移除最后一位
                    partialLine = [ingestedLines lastObject];
                    [ingestedLines removeLastObject];
                }
                //解析每一个数组元素
                for (NSString *line in ingestedLines)
                {
                    //以空格为分割标准
                    NSArray *definitionComponents = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    //提高效率，过滤筛选，为空直接忽略
                    definitionComponents = [definitionComponents filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings)
                                                                                              {
                                                                                                  return ((NSString *)evaluatedObject).length > 0;
                                                                                              }]];
                    if (definitionComponents.count)
                    {
                        //取数组第一位
                        NSString *typeOfDefinition = [definitionComponents objectAtIndex:0];
                        //以数组第一位的字符作为标准进行分析
                        switch ([typeOfDefinition characterAtIndex:0])
                        {
                                //点vertex 法线vertex normal 纹理vertex texture
                            case 'v':
                                //仅是点
                                if (typeOfDefinition.length == 1)
                                {
                                    // This is a vertex definition
                                    self.parserStage = MSHParsingStageVertices;
                                    //顶点应该为3,否则格式编码错误
                                    if (definitionComponents.count != 4)
                                    {
                                        self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"Error parsing a vertex: %@", line]
                                                                       errorCode:MSHParseErrorInvalidVertexDefinition];
                                        self.parserStage = MSHParsingStageError;
                                        return;
                                    }
                                    //取顶点坐标
                                    GLfloat x = [[definitionComponents objectAtIndex:1] floatValue];
                                    GLfloat y = [[definitionComponents objectAtIndex:2] floatValue];
                                    GLfloat z = [[definitionComponents objectAtIndex:3] floatValue];
                                    
                                    amendRange(&outXRange, x);
                                    amendRange(&outYRange, y);
                                    amendRange(&outZRange, z);
                                    //顶点临时存放数组
                                    [tmpVertices addObject:[MSHVertex vertexWithX:x
                                                                                y:y
                                                                                z:z]];
                                    //顶点最大可容载65534
                                    if (tmpVertices.count > MAX_NUM_VERTICES)
                                    {
                                        self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"This model exceeds the maximum number of vertices: %d", MAX_NUM_VERTICES]
                                                                       errorCode:MSHParseErrorVertexNumberLimitExceeded];
                                        self.parserStage = MSHParsingStageError;
                                        return;
                                    }
                                }
                                //vn 法线
                                else if ([typeOfDefinition characterAtIndex:1] == 'n')
                                {
                                    // This is a normal definition
                                    self.parserStage = MSHParsingStageVertexNormals;
                                    if (definitionComponents.count != 4)
                                    {
                                        self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"Error parsing a normal: %@", line]
                                                                       errorCode:MSHParseErrorInvalidNormalDefinition];
                                        self.parserStage = MSHParsingStageError;
                                        return;
                                    }
                                    //法线临时存放数组
                                    [tmpNormals addObject:[NSArray arrayWithObjects:[definitionComponents objectAtIndex:1],
                                                           [definitionComponents objectAtIndex:2],
                                                           [definitionComponents objectAtIndex:3], nil]];
                                }
                                break;
                                //面f
                            case 'f':
                            {
                                // This is a face definition
                                self.parserStage = MSHParsingStageFaces;
                                //面的数量不可小于3个面，否则违背了三角网格
                                if (definitionComponents.count < 4)
                                {
                                    self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"Unexpected number of definition components for face: %@", line]
                                                                   errorCode:MSHParseErrorInvalidFaceDefinition];
                                    self.parserStage = MSHParsingStageError;
                                    return;
                                }
                                //面定义，申请内存等
                                MSHFace face = MSHFaceMake(definitionComponents.count - 1);
                                NSMutableArray *vertexesForNormalCalculation = nil;
                                unsigned int currentFaceIndex = 0;
                                //每一个为 f 1/2/3 2/4/5 3/6/7 再解析
                                for (int i = 1; i < definitionComponents.count; i++)
                                {
                                    //第i个字符串
                                    NSString *definitionComponent = [definitionComponents objectAtIndex:i];
                                    //每个字符串进行分割，标志“/”
                                    NSArray *vertexDefinitionComponents = [definitionComponent componentsSeparatedByString:@"/"];
                                    //分割后大于3表示有问题
                                    if (vertexDefinitionComponents.count > 3)
                                    {
                                        self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"Unexpected number of vertex definition components in face: %@", line]
                                                                       errorCode:MSHParseErrorInvalidFaceDefinition];
                                        self.parserStage = MSHParsingStageError;
                                        return;
                                    }
                                    //vertexIndex：顶点值 , 例如：1/2/3 取分割后第一个点
                                    NSInteger vertexIndex = [[vertexDefinitionComponents objectAtIndex:0] integerValue];
                                    //若不小于0 就－1，取tmpVertices中的相关点
                                    vertexIndex = getIndex(tmpVertices, vertexIndex);
                                    //取tmpVertices中的顶点信息
                                    MSHVertex *vertex = [tmpVertices objectAtIndex:vertexIndex];
                                    //顶点数量
                                    unsigned int suggestedIndex = vertices.count;
                                    id normalId = [NSNull null];
                                    //取法线向量，唯独没有纹理处理
                                    if (vertexDefinitionComponents.count == 3)
                                    {
                                        //取法线值
                                        NSInteger normalIndex = [[vertexDefinitionComponents objectAtIndex:2] integerValue];
                                        //若不小于0 就－1，取tmpNormals中的相关点
                                        normalIndex = getIndex(tmpNormals, normalIndex);
                                        //取tmpVertices中的法线信息
                                        normalId = [tmpNormals objectAtIndex:normalIndex];
                                    }
                                    else
                                    {
                                        // The normal isn't specified. We're going to have to calculate vertices for this face.
                                        //可能面的顶点数大于3
                                        if (!vertexesForNormalCalculation)
                                        {
                                            //自动分配内存
                                            vertexesForNormalCalculation = [NSMutableArray array];
                                        }
                                    }
                                    //加入法线
                                    [vertex addNormalWithNormalId:normalId suggestedIndex:&suggestedIndex];
                                    if (vertexesForNormalCalculation)
                                    {
                                        [vertexesForNormalCalculation addObject:vertex];
                                    }
                                    //修正吗？？？？
                                    if (suggestedIndex == vertices.count)
                                    {
                                        // This vertex has not been used with this normal before.
                                        // We will create a new vertices entry for it.
                                        [vertices addObject:[NSNumber numberWithFloat:vertex.position.x]];
                                        [vertices addObject:[NSNumber numberWithFloat:vertex.position.y]];
                                        [vertices addObject:[NSNumber numberWithFloat:vertex.position.z]];
                                        if ([normalId isKindOfClass:[NSArray class]])
                                        {
                                            [vertices addObject:[normalId objectAtIndex:0]];
                                            [vertices addObject:[normalId objectAtIndex:1]];
                                            [vertices addObject:[normalId objectAtIndex:2]];
                                        }
                                        else
                                        {
                                            // If the vertex normal needs to be calculated, we will put in nulls for now and fill these values in later.
                                            [vertices addObject:[NSNull null]];
                                            [vertices addObject:[NSNull null]];
                                            [vertices addObject:[NSNull null]];
                                        }
                                    }
                                    face.vertexIndices[currentFaceIndex++] = suggestedIndex/6;
                                }
                                if (vertexesForNormalCalculation)
                                {
                                    // Need to calculate the normal for this face
                                    MSHVertex *firstVertex = [vertexesForNormalCalculation objectAtIndex:0];
                                    NSArray *faceNormal = [firstVertex calculateNormalForTriangleFormedWithVertex2:[vertexesForNormalCalculation objectAtIndex:1]
                                                                                                        andVertex3:[vertexesForNormalCalculation objectAtIndex:2]];
                                    for (int vertexIndexWithinFace = 0; vertexIndexWithinFace < face.numVertices; vertexIndexWithinFace++)
                                    {
                                        unsigned int firstNormalIndex = face.vertexIndices[vertexIndexWithinFace]*6 + 3;
                                        MSHVertex *vertex = [tmpVertices objectAtIndex:face.vertexIndices[vertexIndexWithinFace]];
                                        if ([vertices objectAtIndex:firstNormalIndex] == [NSNull null] ||
                                            [vertex usesNormalAveraging])
                                        {
                                            // Need to fill this normal in
                                            GLKVector3 newAverageNormal = [vertex addNormalToAverage:faceNormal];
                                            [vertices replaceObjectAtIndex:firstNormalIndex++ withObject:[NSNumber numberWithFloat:newAverageNormal.x]];
                                            [vertices replaceObjectAtIndex:firstNormalIndex++ withObject:[NSNumber numberWithFloat:newAverageNormal.y]];
                                            [vertices replaceObjectAtIndex:firstNormalIndex withObject:[NSNumber numberWithFloat:newAverageNormal.z]];
                                        }
                                    }
                                }
                                //最终顶点数做个统计比较
                                if (vertices.count/6 > MAX_NUM_VERTICES)
                                {
                                    self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"This model exceeds the maximum number of vertices: %d", MAX_NUM_VERTICES]
                                                                   errorCode:MSHParseErrorVertexNumberLimitExceeded];
                                    self.parserStage = MSHParsingStageError;
                                    return;
                                }
                                [faces addObject:[NSValue valueWithBytes:&face objCType:@encode(MSHFace)]];
                            }
                            default:
                                break;
                        }
                    }
                }
            }
        }
        while (fileData.length == chunkSize);
        NSLog(@"v = %d, vn = %d",[tmpVertices count],[tmpNormals count]);
        //临时数组置空
        tmpVertices = nil;
        tmpNormals = nil;
        //x，y，z轴的大小范围，知道啦！！！！显示作用
        self.xRange = outXRange;
        self.yRange = outYRange;
        self.zRange = outZRange;
        //点、面
        self.vertexCoordinates = vertices;
        self.faces = faces;
        //表示解析了顶点
        if (vertices.count)
        {
            self.parserStage = MSHParsingStageComplete;
        }
        else
        {
            self.parseError = [self errorWithMessage:@"The file does not include any geometry definitions." errorCode:MSHParseErrorNoGeometry];
            self.parserStage = MSHParsingStageError;
        }
    });
}

//面解析要用到
static inline NSUInteger getIndex(NSArray *array, NSInteger objIndex)
{
    if (objIndex < 0)
    {
        objIndex = array.count + objIndex;
    }
    else
    {
        objIndex -= 1;
    }
    return objIndex;
}

@end
