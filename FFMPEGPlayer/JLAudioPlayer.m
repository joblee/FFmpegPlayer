//
//  JLAudioPlayer.m
//  FFMPEGPlayer
//
//  Created by Joblee on 2017/8/23.
//  Copyright © 2017年 Joblee. All rights reserved.
//

#import "JLAudioPlayer.h"

void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ,
                              AudioQueueBufferRef inBuffer);
void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ,
                                 AudioQueuePropertyID inID);

void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ,
                              AudioQueueBufferRef inBuffer) {
    
    JLAudioPlayer *audioController = (__bridge JLAudioPlayer*)inClientData;
    [audioController audioQueueOutputCallback:inAQ inBuffer:inBuffer];
}

void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ,
                                 AudioQueuePropertyID inID) {
    
    JLAudioPlayer *audioController = (__bridge JLAudioPlayer*)inClientData;
    [audioController audioQueueIsRunningCallback];
}

@interface JLAudioPlayer ()

@property (nonatomic, assign) AVCodecContext *audioCodecContext;
@end

@implementation JLAudioPlayer

@synthesize videoPlayer = _videoPlayer;
@synthesize audioCodecContext = _audioCodecContext;

- (id)initWithStreamer:(JLVideoPlayer*)streamer {
    if (self = [super init]) {
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
        _videoPlayer = streamer;
        _audioCodecContext = _videoPlayer.audioCodecContext;
    }
    
    return  self;
}

- (void)dealloc
{
    [self removeAudioQueue];
}


#pragma mark -- 创建音频队列
- (BOOL)createAudioQueue
{
    state_ = AUDIO_STATE_READY;
    finished_ = NO;
    
    if (decodeLock_) {
        [decodeLock_ unlock];
        decodeLock_ = nil;
    }
    
    decodeLock_ = [[NSLock alloc] init];
    
    audioStreamBasicDesc_.mFormatID = -1;
    audioStreamBasicDesc_.mSampleRate = _audioCodecContext->sample_rate;
    
    if (audioStreamBasicDesc_.mSampleRate < 1) {
        audioStreamBasicDesc_.mSampleRate = 32000;
    }
    
    audioStreamBasicDesc_.mFormatFlags = 0;
    
    switch (_audioCodecContext->codec_id) {
        case AV_CODEC_ID_MP3:
        {
            audioStreamBasicDesc_.mFormatID = kAudioFormatMPEGLayer3;
            break;
        }
        case AV_CODEC_ID_AAC:
        {
            audioStreamBasicDesc_.mFormatID = kAudioFormatMPEG4AAC;
            audioStreamBasicDesc_.mFormatFlags = kMPEG4Object_AAC_LC;
            audioStreamBasicDesc_.mSampleRate = 44100;
            audioStreamBasicDesc_.mChannelsPerFrame = 2;
            audioStreamBasicDesc_.mBitsPerChannel = 0;
            audioStreamBasicDesc_.mFramesPerPacket = 1024;
            audioStreamBasicDesc_.mBytesPerPacket = 0;
            
            break;
        }
        case AV_CODEC_ID_AC3:
        {
            audioStreamBasicDesc_.mFormatID = kAudioFormatAC3;
            break;
        }
        case AV_CODEC_ID_PCM_MULAW:
        {
            audioStreamBasicDesc_.mFormatID = kAudioFormatULaw;
            audioStreamBasicDesc_.mSampleRate = 8000.0;
            audioStreamBasicDesc_.mFormatFlags = 0;
            audioStreamBasicDesc_.mFramesPerPacket = 1;
            audioStreamBasicDesc_.mChannelsPerFrame = 1;
            audioStreamBasicDesc_.mBitsPerChannel = 8;
            audioStreamBasicDesc_.mBytesPerPacket = 1;
            audioStreamBasicDesc_.mBytesPerFrame = 1;
            break;
        }
        default:
        {
            audioStreamBasicDesc_.mFormatID = kAudioFormatAC3;
            break;
        }
    }
#pragma mark -- 设置音频输出(播放)回调
    OSStatus status = AudioQueueNewOutput(&audioStreamBasicDesc_, audioQueueOutputCallback, (__bridge void*)self, NULL, NULL, 0, &audioQueue_);
    if (status != noErr) {
        NSLog(@"无法创建AudioQueueNewOutput");
        return NO;
    }
#pragma mark -- 设置音频播放监听(是否正常运行)
    status = AudioQueueAddPropertyListener(audioQueue_, kAudioQueueProperty_IsRunning, audioQueueIsRunningCallback, (__bridge void*)self);
    if (status != noErr) {
        NSLog(@"无法添加监听");
        return NO;
    }
#pragma mark -- 设置播放缓冲区
    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
        status = AudioQueueAllocateBufferWithPacketDescriptions(audioQueue_,
                                                                audioStreamBasicDesc_.mSampleRate * kAudioBufferSeconds / 8,
                                                                _audioCodecContext->sample_rate * kAudioBufferSeconds / (_audioCodecContext->frame_size + 1),
                                                                &audioQueueBuffer_[i]);
        if (status != noErr) {
            NSLog(@"无法创建缓冲区");
            return NO;
        }
    }
    
    return YES;
}
- (IBAction)playAudio:(UIButton*)sender
{
    [self _startAudio];
}

- (IBAction)pauseAudio:(UIButton*)sender
{
    if (started_) {
        state_ = AUDIO_STATE_PAUSE;
        
        AudioQueuePause(audioQueue_);
        AudioQueueReset(audioQueue_);
    }
}
#pragma mark -- 启动音频播放
- (void)_startAudio
{
    if (started_) {
        AudioQueueStart(audioQueue_, NULL);
    } else {
        [self createAudioQueue] ;
        [self startQueue];
    }
    
    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
        [self enqueueBuffer:audioQueueBuffer_[i]];
    }
    
    state_ = AUDIO_STATE_PLAYING;
}
#pragma mark -- 停止音频播放
- (void)_stopAudio
{
    if (started_) {
        AudioQueueStop(audioQueue_, YES);
        startedTime_ = 0.0;
        state_ = AUDIO_STATE_STOP;
        finished_ = NO;
    }
}
#pragma mark -- 移除音频队列
- (void)removeAudioQueue
{
    [self _stopAudio];
    started_ = NO;
    
    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
        AudioQueueFreeBuffer(audioQueue_, audioQueueBuffer_[i]);
    }
    
    AudioQueueDispose(audioQueue_, YES);
    
    if (decodeLock_) {
        [decodeLock_ unlock];
        decodeLock_ = nil;
    }
}

#pragma mark -- 音频队列回调
- (void)audioQueueOutputCallback:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer
{
    if (state_ == AUDIO_STATE_PLAYING) {
        [self enqueueBuffer:inBuffer];
    }
}
#pragma mark -- 监测音频队列的状态
- (void)audioQueueIsRunningCallback
{
    UInt32 isRunning;
    UInt32 size = sizeof(isRunning);
    OSStatus status = AudioQueueGetProperty(audioQueue_, kAudioQueueProperty_IsRunning, &isRunning, &size);
    
    if (status == noErr && !isRunning && state_ == AUDIO_STATE_PLAYING) {
        state_ = AUDIO_STATE_STOP;
        
        if (finished_) {
        }
    }
}
#pragma mark -- 将要播放的音频数据推进缓冲区
//audio queue播放完后返回空的缓冲区，我们只需往缓冲区填入数据
- (OSStatus)enqueueBuffer:(AudioQueueBufferRef)buffer
{
    OSStatus status = noErr;
    
    if (buffer) {
        AudioTimeStamp bufferStartTime;
        buffer->mAudioDataByteSize = 0;
        buffer->mPacketDescriptionCount = 0;
        //        _streamer:RTSPPlayer       audioPacketQueue：array
        if (_videoPlayer.audioPacketQueue.count <= 0) {
            _videoPlayer.emptyAudioBuffer = buffer;
            return status;
        }
        //       emptyAudioBuffer： AudioQueueBufferRef
        _videoPlayer.emptyAudioBuffer = nil;
        
        while (_videoPlayer.audioPacketQueue.count && buffer->mPacketDescriptionCount < buffer->mPacketDescriptionCapacity) {
            
            //AVPacket：FFmpeg解码库中的类
            AVPacket *packet = [_videoPlayer readPacket];//读取音频数据
            
            if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= packet->size) {
                if (buffer->mPacketDescriptionCount == 0) {
                    bufferStartTime.mSampleTime = packet->dts * _audioCodecContext->frame_size;
                    bufferStartTime.mFlags = kAudioTimeStampSampleTimeValid;
                }
                //copy到缓冲区
                memcpy((uint8_t *)buffer->mAudioData + buffer->mAudioDataByteSize, packet->data, packet->size);
                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = packet->size;
                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = _audioCodecContext->frame_size;
                
                buffer->mAudioDataByteSize += packet->size;
                buffer->mPacketDescriptionCount++;
                
                //
                _videoPlayer.audioPacketQueueSize -= packet->size;
                //释放空间
                av_free_packet(packet);
            }
            else {
                break;
            }
        }
        
        [decodeLock_ lock];
        if (buffer->mPacketDescriptionCount > 0) {
            //缓冲区重新入列
            status = AudioQueueEnqueueBuffer(audioQueue_, buffer, 0, NULL);
            if (status != noErr) {
                NSLog(@"无法添加到缓冲区");
            }
        } else {
            AudioQueueStop(audioQueue_, NO);
            finished_ = YES;
        }
        
        [decodeLock_ unlock];
    }
    
    return status;
}
#pragma mark -- 启动音频队列
- (OSStatus)startQueue
{
    OSStatus status = noErr;
    
    if (!started_) {
        status = AudioQueueStart(audioQueue_, NULL);
        if (status == noErr) {
            started_ = YES;
        }
        else {
            NSLog(@"无法启动 audio queue.");
        }
    }
    
    return status;
}

@end
