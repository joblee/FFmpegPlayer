//
//  JLVideoPlayer.m
//  FFMPEGPlayer
//
//  Created by Joblee on 2017/8/24.
//  Copyright © 2017年 Joblee. All rights reserved.
//

#import "JLVideoPlayer.h"
#import "Utilities.h"
#import "JLAudioPlayer.h"

@interface JLVideoPlayer ()
@property (nonatomic, retain) JLAudioPlayer *audioController;
@end

@interface JLVideoPlayer (private)
-(void)convertFrameToRGB;
-(UIImage *)imageFromAVPicture:(AVPicture)pict width:(int)width height:(int)height;
-(void)savePicture:(AVPicture)pFrame width:(int)width height:(int)height index:(int)iFrame;
-(void)setupScaler;
@end

@implementation JLVideoPlayer

@synthesize audioController = _audioController;
@synthesize audioPacketQueue,audioPacketQueueSize;
@synthesize _audioStream, audioCodecContext;
@synthesize emptyAudioBuffer;

@synthesize outputWidth, outputHeight;
#pragma mark --设置输出视频的宽度
- (void)setOutputWidth:(int)newValue
{
    if (outputWidth != newValue) {
        outputWidth = newValue;
        [self setupScaler];
    }
}
#pragma mark --设置输出视频的高度
- (void)setOutputHeight:(int)newValue
{
    if (outputHeight != newValue) {
        outputHeight = newValue;
        [self setupScaler];
    }
}
#pragma mark -- 获取当前图片
- (UIImage *)currentImage
{
    //取出解码后的帧数据
    if (!pFrame->data[0]) return nil;
    //转换成RGB
    [self convertFrameToRGB];
    //根据指定宽高裁剪出图片并返回
    return [self imageFromAVPicture:picture width:outputWidth height:outputHeight];
}

- (double)duration
{
    return (double)pFormatCtx->duration / AV_TIME_BASE;
}
//当前播放的时间
- (double)currentTime
{
    AVRational timeBase = pFormatCtx->streams[videoStream]->time_base;
    return packet.pts * (double)timeBase.num / timeBase.den;
}
#pragma mark --获取视频源的宽高
- (int)sourceWidth
{
    return pCodecCtx->width;
}

- (int)sourceHeight
{
    return pCodecCtx->height;
}
#pragma mark --设置输出视频的高度
- (id)initWithURL:(NSString *)moviePath
{
    if (!(self=[super init])) return nil;
    
    AVCodec         *pCodec;
    
    // 注册所有的编解码器
    avcodec_register_all();
    //初始化格式及传输协议
    av_register_all();
    //初始化全局网络组件
    avformat_network_init();
    
    // 设置RTSP选项
    AVDictionary *opts = 0;
    BOOL isTcp = YES;
    if (isTcp)
        av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    
    //根据URL打开一个输入流或local视频文件并读取头部信息
    if (avformat_open_input(&pFormatCtx, [moviePath UTF8String], NULL, &opts) !=0 ) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
        goto initError;
    }
    
    // 检索视频流信息
    if (avformat_find_stream_info(pFormatCtx,NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't find stream information\n");
        goto initError;
    }
    
    // Find the first video stream
    videoStream=-1;
    audioStream=-1;
    
    for (int i=0; i<pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO) {
            NSLog(@"found video stream");
            videoStream=i;
        }
        
        if (pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO) {
            audioStream=i;
            NSLog(@"found audio stream");
        }
    }
    
    if (videoStream==-1 && audioStream==-1) {
        goto initError;
    }
    
    //获取一个指向视频流编解码器上下文的指针
    pCodecCtx = pFormatCtx->streams[videoStream]->codec;
    
    // 获取视频编码格式
    pCodec = avcodec_find_decoder(pCodecCtx->codec_id);
    if (pCodec == NULL) {
        av_log(NULL, AV_LOG_ERROR, "Unsupported codec!\n");
        goto initError;
    }
    
    // 根据上面的视频格式打开编解码器
    if (avcodec_open2(pCodecCtx, pCodec, NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open video decoder\n");
        goto initError;
    }
    
    if (audioStream > -1 ) {
        //创建一个音频解码器
        [self setupAudioDecoder];
    }
    
    // 创建一个AVFrame并设置默认值的字段
    pFrame = av_frame_alloc();
    
    outputWidth = pCodecCtx->width;
    self.outputHeight = pCodecCtx->height;
    
    return self;
    
initError:
    return nil;
}

#pragma mark -- 设置计数器
- (void)setupScaler
{
    // 释放旧图片和计数器
    avpicture_free(&picture);
    sws_freeContext(img_convert_ctx);
    
    // 创建一个AVPicture
    avpicture_alloc(&picture, AV_PIX_FMT_RGB24, outputWidth, outputHeight);
    
    // 设置计数器
    static int sws_flags =  SWS_FAST_BILINEAR;
    img_convert_ctx = sws_getContext(pCodecCtx->width,
                                     pCodecCtx->height,
                                     pCodecCtx->pix_fmt,
                                     outputWidth,
                                     outputHeight,
                                     AV_PIX_FMT_RGB24,
                                     sws_flags, NULL, NULL, NULL);
    
}
#pragma mark -- 根据指定时间寻找关键帧
- (void)seekTime:(double)seconds
{
    AVRational timeBase = pFormatCtx->streams[videoStream]->time_base;
    int64_t targetFrame = (int64_t)((double)timeBase.den / timeBase.num * seconds);
    avformat_seek_file(pFormatCtx, videoStream, targetFrame, targetFrame, targetFrame, AVSEEK_FLAG_FRAME);
    avcodec_flush_buffers(pCodecCtx);
}

- (void)dealloc
{
    // Free scaler
    sws_freeContext(img_convert_ctx);
    
    // Free RGB picture
    avpicture_free(&picture);
    
    // Free the packet that was allocated by av_read_frame
    av_free_packet(&packet);
    
    // Free the YUV frame
    av_free(pFrame);
    
    // Close the codec
    if (pCodecCtx) avcodec_close(pCodecCtx);
    
    // Close the video file
    if (pFormatCtx) avformat_close_input(&pFormatCtx);
    
    [_audioController _stopAudio];
    _audioController = nil;
    
    audioPacketQueue = nil;
    
    audioPacketQueueLock = nil;
}
#pragma mark -- 从视频流中读取下一帧
- (BOOL)stepFrame
{
    // AVPacket packet;
    int frameFinished=0;
    
    while (!frameFinished && av_read_frame(pFormatCtx, &packet) >=0 ) {
        // 判断是音频还是视频
        if(packet.stream_index==videoStream) {
            // 将该帧解码，将h264（packet）解码成YUV（pFrame）
            avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, &packet);
        }
        
        if (packet.stream_index==audioStream) {
            [audioPacketQueueLock lock];
            
            audioPacketQueueSize += packet.size;
            [audioPacketQueue addObject:[NSMutableData dataWithBytes:&packet length:sizeof(packet)]];
            
            [audioPacketQueueLock unlock];
            
            if (!primed) {
                primed=YES;
                //启动音频播放器
                [_audioController _startAudio];
            }
            
            if (emptyAudioBuffer) {
                [_audioController enqueueBuffer:emptyAudioBuffer];
            }
        }
    }
    
    return frameFinished!=0;
}
#pragma mark -- 将YUV转换成RGB
- (void)convertFrameToRGB
{   //yuv420p to rgb24
    sws_scale(img_convert_ctx,
              (const uint8_t *const *)pFrame->data,
              pFrame->linesize,
              0,
              pCodecCtx->height,
              picture.data,
              picture.linesize);
}


#pragma mark -- 初始化音频解码器
- (void)setupAudioDecoder
{
    if (audioStream >= 0) {
        _audioBufferSize = 192000;
        _audioBuffer = av_malloc(_audioBufferSize);
        _inBuffer = NO;
        
        audioCodecContext = pFormatCtx->streams[audioStream]->codec;
        _audioStream = pFormatCtx->streams[audioStream];
        
        AVCodec *codec = avcodec_find_decoder(audioCodecContext->codec_id);
        if (codec == NULL) {
            NSLog(@"Not found audio codec.");
            return;
        }
        
        if (avcodec_open2(audioCodecContext, codec, NULL) < 0) {
            NSLog(@"Could not open audio codec.");
            return;
        }
        
        if (audioPacketQueue) {
            audioPacketQueue = nil;
        }
        audioPacketQueue = [[NSMutableArray alloc] init];
        
        if (audioPacketQueueLock) {
            audioPacketQueueLock = nil;
        }
        audioPacketQueueLock = [[NSLock alloc] init];
        
        if (_audioController) {
            [_audioController _stopAudio];
            _audioController = nil;
        }
        _audioController = [[JLAudioPlayer alloc] initWithStreamer:self];
    } else {
        pFormatCtx->streams[audioStream]->discard = AVDISCARD_ALL;
        audioStream = -1;
    }
}

- (void)nextPacket
{
    _inBuffer = NO;
}
#pragma mark -- 读取数据包
- (AVPacket*)readPacket
{
    if (_currentPacket.size > 0 || _inBuffer) return &_currentPacket;
    
    NSMutableData *packetData = [audioPacketQueue objectAtIndex:0];
    _packet = [packetData mutableBytes];
    
    if (_packet) {
        if (_packet->dts != AV_NOPTS_VALUE) {
            _packet->dts += av_rescale_q(0, AV_TIME_BASE_Q, _audioStream->time_base);
        }
        
        if (_packet->pts != AV_NOPTS_VALUE) {
            _packet->pts += av_rescale_q(0, AV_TIME_BASE_Q, _audioStream->time_base);
        }
        
        [audioPacketQueueLock lock];
        audioPacketQueueSize -= _packet->size;
        if ([audioPacketQueue count] > 0) {
            [audioPacketQueue removeObjectAtIndex:0];
        }
        [audioPacketQueueLock unlock];
        
        _currentPacket = *(_packet);
    }
    
    return &_currentPacket;
}

- (void)closeAudio
{
    [_audioController _stopAudio];
    primed=NO;
}
//保存ppm格式的图片
- (void)savePPMPicture:(AVPicture)pict width:(int)width height:(int)height index:(int)iFrame
{
    FILE *pFile;
    NSString *fileName;
    int  y;
    
    fileName = [Utilities documentsPath:[NSString stringWithFormat:@"image%04d.ppm",iFrame]];
    // Open file
    NSLog(@"write image file: %@",fileName);
    pFile=fopen([fileName cStringUsingEncoding:NSASCIIStringEncoding], "wb");
    if (pFile == NULL) {
        return;
    }
    
    // Write header
    fprintf(pFile, "P6\n%d %d\n255\n", width, height);
    
    // Write pixel data
    for (y=0; y<height; y++) {
        fwrite(pict.data[0]+y*pict.linesize[0], 1, width*3, pFile);
    }
    
    // Close file
    fclose(pFile);
}
- (UIImage *)imageFromAVPicture:(AVPicture)pict width:(int)width height:(int)height
{
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, pict.data[0], pict.linesize[0]*height,kCFAllocatorNull);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate(width,
                                       height,
                                       8,
                                       24,
                                       pict.linesize[0],
                                       colorSpace,
                                       bitmapInfo,
                                       provider,
                                       NULL,
                                       NO,
                                       kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    
    CGImageRelease(cgImage);
    CGDataProviderRelease(provider);
    CFRelease(data);
    
    return image;
}

@end

