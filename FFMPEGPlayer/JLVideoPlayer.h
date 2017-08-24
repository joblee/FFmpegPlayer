//
//  JLVideoPlayer.h
//  FFMPEGPlayer
//
//  Created by Joblee on 2017/8/24.
//  Copyright © 2017年 Joblee. All rights reserved.
//
#import <Foundation/Foundation.h>
#import "avformat.h"
#import "avcodec.h"
#import "avio.h"
#import "swscale.h"
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioToolbox.h>

@interface JLVideoPlayer : NSObject {
    //统领全局的基本结构体。主要用于处理封装格式（FLV/MKV/RMVB等）
    AVFormatContext *pFormatCtx;
    //描述编解码器上下文的数据结构，包含了众多编解码器需要的参数信息
    AVCodecContext *pCodecCtx;
    //存储非压缩的数据（视频对应RGB/YUV像素数据，音频对应PCM采样数据）
    AVFrame *pFrame;
    //媒体流信息
    AVStream *_audioStream;
    //存储压缩数据（视频对应H.264等码流数据，音频对应AAC/MP3等码流数据）
    AVPacket packet;
    AVPicture picture;
    AVPacket *_packet, _currentPacket;
    int videoStream;
    int audioStream;
    struct SwsContext *img_convert_ctx;
    int sourceWidth, sourceHeight;
    int outputWidth, outputHeight;
    UIImage *currentImage;
    double duration;
    double currentTime;
    NSLock *audioPacketQueueLock;
    int16_t *_audioBuffer;
    int audioPacketQueueSize;
    NSMutableArray *audioPacketQueue;
    NSUInteger _audioBufferSize;
    BOOL _inBuffer;
    BOOL primed;
    
    
}

// 上一次解码的图片作为 UIImage
@property (nonatomic, readonly) UIImage *currentImage;

// 源视频的宽高 */
@property (nonatomic, readonly) int sourceWidth, sourceHeight;

// 设置输出image的宽高
@property (nonatomic) int outputWidth, outputHeight;

// 视频的长度，秒为单位
@property (nonatomic, readonly) double duration;

// 视频当前的时间
@property (nonatomic, readonly) double currentTime;

@property (nonatomic, strong) NSMutableArray *audioPacketQueue;
@property (nonatomic, assign) AVCodecContext *audioCodecContext;
@property (nonatomic, assign) AudioQueueBufferRef emptyAudioBuffer;
@property (nonatomic, assign) int audioPacketQueueSize;
@property (nonatomic, assign) AVStream *_audioStream;


-(id)initWithURL:(NSString *)moviePath;

//从视频流中读取下一帧，可能会出现找不到的情况，因为视频传输完成了
-(BOOL)stepFrame;

//根据指定时间寻找关键帧
-(void)seekTime:(double)seconds;

-(void)closeAudio;

- (AVPacket*)readPacket;

@end
