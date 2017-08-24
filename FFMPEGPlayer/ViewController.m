//
//  ViewController.m
//  FFMPEGPlayer
//
//  Created by Joblee on 2017/8/23.
//  Copyright © 2017年 Joblee. All rights reserved.
//

#import "ViewController.h"
#import "JLVideoPlayer.h"
@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@end

@implementation ViewController
@synthesize video;

- (void)viewDidLoad {
    [super viewDidLoad];
    video = [[JLVideoPlayer alloc] initWithURL:@"rtmp://192.168.2.28:1935/rtmpTest/room" ];
    video.outputWidth = self.imageView.frame.size.width/2;
    video.outputHeight = self.imageView.frame.size.height/2;
    
}
- (void)viewWillAppear:(BOOL)animated {
    //使用一个定时器来不断播放视频帧
    [self displayNextFrame];
}

-(void)displayNextFrame
{
    [self performSelector:@selector(displayNextFrame) withObject:nil afterDelay:1.0/24];
    if (![video stepFrame]) {
        [video closeAudio];
        return;
    }
    _imageView.image = video.currentImage;
}


@end
