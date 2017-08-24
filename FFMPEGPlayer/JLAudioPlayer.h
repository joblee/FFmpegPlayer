//
//  JLAudioPlayer.h
//  FFMPEGPlayer
//
//  Created by Joblee on 2017/8/23.
//  Copyright © 2017年 Joblee. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "JLVideoPlayer.h"
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#define kNumAQBufs 3//缓冲区数量
#define kAudioBufferSeconds 3

typedef enum _AUDIO_STATE {
    AUDIO_STATE_READY           = 0,
    AUDIO_STATE_STOP            = 1,
    AUDIO_STATE_PLAYING         = 2,
    AUDIO_STATE_PAUSE           = 3,
    AUDIO_STATE_SEEKING         = 4
} AUDIO_STATE;

@interface JLAudioPlayer : NSObject
{
    NSString *playingFilePath_;
    AudioStreamBasicDescription audioStreamBasicDesc_;
    AudioQueueRef audioQueue_;
    AudioQueueBufferRef audioQueueBuffer_[kNumAQBufs];
    BOOL started_, finished_;
    NSTimeInterval durationTime_, startedTime_;
    NSInteger state_;
    NSTimer *seekTimer_;
    NSLock *decodeLock_;
    AVCodecContext *_audioCodecContext;
}

@property (nonatomic, strong) JLVideoPlayer *videoPlayer;

- (void)_startAudio;
- (void)_stopAudio;
- (BOOL)createAudioQueue;
- (void)removeAudioQueue;
- (void)audioQueueOutputCallback:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer;
- (void)audioQueueIsRunningCallback;
- (OSStatus)enqueueBuffer:(AudioQueueBufferRef)buffer;
- (id)initWithStreamer:(JLVideoPlayer*)audioPlayer;

- (OSStatus)startQueue;

@end
