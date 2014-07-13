//
//  MSHFile.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MSHFile.h"
#import "MSHVertex.h"

@interface MSHFile()

@property (nonatomic, readwrite, strong) NSURL *localURL;
@property (nonatomic, readwrite, strong) MSHVertex *outlierVertex;
@property (nonatomic, readwrite, assign) MSHFileStatus status;
@property (nonatomic, readwrite, strong) void (^onStatusUpdateBlock)(MSHFile *);
@property (nonatomic, readwrite, strong) NSError *processingError;

@end

@implementation MSHFile

- (id)initWithURL:(NSURL *)url
{
    if (self = [super init])
    {
        NSAssert([[NSFileManager defaultManager] fileExistsAtPath:[url path]], @"File doesn't exist at the provided path.");
        self.localURL = url;
    }
    return self;
}

- (void)parseWithStatusUpdateBlock:(void (^)(MSHFile *))statusUpdateBlock
{
    NSAssert(self.localURL, @"Must have the file locally in order to parse it.");
    //指针交换，意在不需要申请类对象，类似于statusupdateblock为一个返回指针，在其他控制器都可以使用
    self.onStatusUpdateBlock = statusUpdateBlock;
    //顶点数若不为空
    if (self.vertexCoordinates)
    {
        self.status = MSHParsingStageComplete;
    }
    else
    {
        //通过块申请解析类对象，通过块来解析，明了，清晰
        MSHParser *parser = [[MSHParser alloc] initWithFileURL:self.localURL];
        [parser parseFileWithStatusChangeBlock:^(MSHParser *changedParser)
         {
             //监听解析过程中变化情况，一旦变化执行相应代码，同时也传递到上一级调用函数处
             switch (changedParser.parserStage)
             {
                 case MSHParsingStageError:
                     self.processingError = changedParser.parseError;
                     self.status = MSHFileStatusFailure;
                     break;
                 case MSHParsingStageComplete:
                 {
                     self.status = MSHFileStatusCalibrating;
                     dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
                    {
                        _numFaces = changedParser.faces.count; //面的数量
                        //c语言中的数组意思 存放每个face类型数据
                        _numVerticesInFace = malloc(sizeof(GLubyte)*_numFaces); //申请内存
                        MSHFace face;
                        int i = 0;
                        //总索引数量，即顶点数量
                        int numIndices = 0;
                        for (NSValue *faceValue in changedParser.faces)
                        {
                            [faceValue getValue:&face];
                            //用完自增，用作存储每个面中顶点个数
                            _numVerticesInFace[i++] = face.numVertices;
                            numIndices += face.numVertices;
                        }
                        if (numIndices)
                        {
                            //存储面中顶点索引 并相应分配内存
                            _vertexIndicesSize = sizeof(GLushort)*numIndices;
                            //相当于顶点数组
                            _vertexIndices = malloc(_vertexIndicesSize);
                        }
                        //以下相当于在vertexIndices中加入顶点值
                        i = 0;
                        for (int faceIndex = 0; faceIndex < _numFaces; faceIndex++)
                        {
                            [[changedParser.faces objectAtIndex:faceIndex] getValue:&face];
                            for (int j = 0; j < _numVerticesInFace[faceIndex]; j++)
                            {
                                _vertexIndices[i++] = face.vertexIndices[j];
                            }
                        }
                        
                        //顶点处理，获取顶点数，计算内存大小
                        _vertexCoordinatesSize = changedParser.vertexCoordinates.count*sizeof(GLfloat);
                        //相当于给数组分配内存，然后在装载顶点值
                        _vertexCoordinates = malloc(_vertexCoordinatesSize);
                        i = 0;
                        for (NSNumber *floatNumber in changedParser.vertexCoordinates)
                        {
                            _vertexCoordinates[i++] = [floatNumber floatValue];
                        }
                        
                        //获取中心点
                        MSHVertex *centerVertex = [MSHVertex vertexWithX:getMidpoint(changedParser.xRange) y:getMidpoint(changedParser.yRange) z:getMidpoint(changedParser.zRange)];
                        GLfloat maxDistance = 0;
                        //局外点
                        MSHVertex *outlier;
                        for (int i = 0; i < changedParser.faces.count; i++)
                        {
                            MSHFace face;
                            [[changedParser.faces objectAtIndex:i] getValue:&face];
                            for (int j = 0; j < face.numVertices; j++)
                            {
                                //????
                                unsigned int verticeStartIndex = face.vertexIndices[j]*6;
                                MSHVertex *vertex = [MSHVertex vertexWithX:self.vertexCoordinates[verticeStartIndex]
                                                                         y:self.vertexCoordinates[verticeStartIndex + 1]
                                                                         z:self.vertexCoordinates[verticeStartIndex + 2]];
                                GLfloat distance = [centerVertex distanceToVertex:vertex];
                                if (distance > maxDistance)
                                {
                                    maxDistance = distance;
                                    outlier = vertex;
                                }
                            }
                        }
                        //其他变量传递
                        _xRange = changedParser.xRange;
                        _yRange = changedParser.yRange;
                        _zRange = changedParser.zRange;
                        self.outlierVertex = outlier;
                        self.status = MSHFileStatusReady;
                    });
                 }
                    break;
                 case MSHParsingStageVertices:
                     self.status = MSHFileStatusParsingVertices;
                     break;
                 case MSHParsingStageVertexNormals:
                     self.status = MSHFileStatusParsingVertexNormals;
                     break;
                 case MSHParsingStageFaces:
                     self.status = MSHFileStatusParsingFaces;
                     break;
                 default:
                     self.status = MSHFileStatusUnknown;
                     break;
             }
         }];
    }
}

//执行触发上一级调用函数
- (void)setStatus:(MSHFileStatus)status
{
    BOOL needToNotify = _status != status;
    _status = status;
    if (needToNotify && self.onStatusUpdateBlock)
    {
        dispatch_async(dispatch_get_main_queue(), ^
        {
            __weak MSHFile *me = self;
            self.onStatusUpdateBlock(me);
        });
    }
}

- (void)dealloc
{
    free(_vertexCoordinates);
    free(_vertexIndices);
}


@end
