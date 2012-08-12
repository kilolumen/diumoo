//
//  DMPlayableCapsule.m
//  diumoo-core
//
//  Created by Shanzi on 12-5-31.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#define kTimerPulseTypePlay @"kTimerPulseTypePlay"
#define kTimerPulseTypePause @"kTimerPulseTypePause"
#define KTimerPulseTypeVolumeChange @"kTimerPulseTypeVolumeChange"

#import <math.h>
#import "DMPlayableCapsule.h"

@implementation DMPlayableCapsule

@synthesize loadState,playState;
@synthesize like,length,rating_avg;
@synthesize aid,sid,ssid,subtype,title,artist,albumtitle;
@synthesize albumLocation,musicLocation,pictureLocation,largePictureLocation;
@synthesize picture,movie,delegate;

+(id)playableCapsuleWithDictionary:(NSDictionary *)dic
{
    return [[DMPlayableCapsule alloc] initWithDictionary:dic];
}

-(void)dealloc
{
    [self invalidateMovie];
}

-(id)initWithDictionary:(NSDictionary *)dic
{
    if (self = [super init]) {
        loadState = QTMovieLoadStateError;

        timer = [[NSTimer alloc] init];

        aid = [dic valueForKey:@"aid"]; 
        sid = [dic valueForKey:@"sid"];
        ssid = [dic valueForKey:@"ssid"];
        subtype = [dic valueForKey:@"subtype"];
        title = [dic valueForKey:@"title"];
        artist = [dic valueForKey:@"artist"];
        albumtitle = [dic valueForKey:@"albumtitle"];
        albumLocation = [NSString stringWithFormat:@"%@%@",DOUBAN_URL_PRIFIX,[dic valueForKey:@"album"]];
        musicLocation = [dic valueForKey:@"url"];
        pictureLocation = [dic valueForKey:@"picture"];
        largePictureLocation = [pictureLocation stringByReplacingOccurrencesOfString:@"mpic" withString:@"lpic"];
        
        like = [[dic valueForKey:@"like"] boolValue];
        length = [[dic valueForKey:@"length"] floatValue] * 1000;
        rating_avg = [[dic valueForKey:@"rating_avg"] floatValue];
        
        volume = [[[NSUserDefaults standardUserDefaults] valueForKey:@"volume"] floatValue];
    }
    return self;
}

-(BOOL) createNewMovie
{
    if(loadState >= QTMovieLoadStatePlaythroughOK) 
        return YES;
    
    playState = WAIT_TO_PLAY;
    
    NSError* err = nil;
    QTMovie* m = [QTMovie movieWithURL:[NSURL URLWithString:musicLocation] error:&err];
    
    if(!err)
    {
        [self invalidateMovie];
        movie = m;

        // 添加新的侦听
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(movieRateDidChanged:) 
                                                     name:QTMovieRateDidChangeNotification 
                                                   object:movie];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(movieLoadStateDidChanged:) 
                                                     name:QTMovieLoadStateDidChangeNotification
                                                   object:movie];
        return YES;
    }
    return NO;
}

-(void) invalidateMovie
{
    // 删除notification侦听
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    loadState = -1;
    playState = WAIT_TO_PLAY;
    [movie invalidate];
}

-(void) movieRateDidChanged:(NSNotification* )n
{
    
    if (movie.rate > 0) {
        [self.delegate playableCapsuleDidPlay:self];
    }
    else if (
        (movie.duration.timeValue - movie.currentTime.timeValue) < 100) {
        [self.delegate playableCapsuleDidEnd:self];
    }
    else {
        [self.delegate playableCapsuleDidPause:self];
    }
}

-(void) movieLoadStateDidChanged:(NSNotification*)n
{
    loadState = [[movie attributeForKey:QTMovieLoadStateAttribute] longValue];
    [self.delegate playableCapsule:self loadStateChanged:loadState];
}

-(void) play
{
    if(loadState < QTMovieLoadStatePlayable)
        return;
    
    if(playState == WAIT_TO_PLAY)
    {
        playState = PLAYING;
        [movie setVolume: volume];
    }
    else
        playState = REPLAYING;
    
    if(movie && movie.rate == 0.0){
        if(timer)
            [timer invalidate];
        
        timer = [NSTimer timerWithTimeInterval:TIMER_INTERVAL
                                        target:self
                                      selector:@selector(timerPulse:)
                                      userInfo:kTimerPulseTypePlay
                                       repeats:YES];
        CFRunLoopAddTimer(CFRunLoopGetMain(), (__bridge CFRunLoopTimerRef)timer, kCFRunLoopCommonModes);
        
        [timer fire];
        
        [movie autoplay];
            
        DMLog(@"rate after play called = %lf, volume = %lf",movie.rate,movie.volume);

    }
    else {
        [self.delegate playableCapsuleDidPlay:self];
    }
}

-(void) pause
{
    if(movie && movie.rate == 1.0){
        if(timer)
            [timer invalidate];
        
        timer = [NSTimer timerWithTimeInterval:TIMER_INTERVAL 
                                        target:self 
                                      selector:@selector(timerPulse:) 
                                      userInfo:kTimerPulseTypePause
                                       repeats:YES];
        
        CFRunLoopAddTimer(CFRunLoopGetMain(), (__bridge CFRunLoopTimerRef)timer, kCFRunLoopCommonModes);
        [self.delegate playableCapsuleWillPause:self];
        [timer fire];
    }
    else
        [self.delegate playableCapsuleDidPause:self];
}

-(void) replay
{
    [movie stop];
    [movie gotoBeginning];
    [self play];
}

-(void) invalidateTimer
{
    CFRunLoopRemoveTimer(CFRunLoopGetMain(),(__bridge CFRunLoopTimerRef) timer, kCFRunLoopCommonModes);
    [timer invalidate];
    timer = nil;
}

-(void) timerPulse:(NSTimer*)t
{
    float delta =  volume - movie.volume;
        
    if([timer userInfo] == kTimerPulseTypePlay)
    {
        if(abs(delta) < 0.08)
        {
            [self invalidateTimer];
            movie.volume = volume;
        }
        else {
            DMLog(@"time pulse delta = %lf - %lf",volume,movie.volume);
            movie.volume += delta>0?0.08:-0.08;
        }
    }
    else if([timer userInfo] == kTimerPulseTypePause)
    {
        if(movie.volume > 0.0 && movie.rate > 0) movie.volume -= 0.08;
        else {
            [self invalidateTimer];
            [movie stop];
        }
    }
    else {
        DMLog(@"%f",delta);
        if (delta < 0.1 && -delta < 0.1) {
            [self invalidateTimer];
            movie.volume = volume;
        }
        else {
            movie.volume += delta>0?0.08:-0.08;
        }
    }
}

-(void) commitVolume:(float)targetVolume
{
    DMLog(@"commit volume");
    volume = targetVolume;

    [[[NSUserDefaultsController sharedUserDefaultsController] values] setValue:@(targetVolume)
                                                                        forKey:@"volume"];
    
    if(movie.rate == 0.0)
        return;
    else{
        if(timer) return;
        
        timer = [NSTimer timerWithTimeInterval:TIMER_INTERVAL
                                        target:self
                                      selector:@selector(timerPulse:)
                                      userInfo:KTimerPulseTypeVolumeChange
                                       repeats:YES];
        
        CFRunLoopAddTimer(CFRunLoopGetMain(), (__bridge CFRunLoopTimerRef)timer, kCFRunLoopCommonModes);
        [self.delegate playableCapsuleWillPause:self];
        [timer fire];
    }
}

-(NSString*) startAttributeWithChannel:(NSString *)channel
{
    if(ssid==nil) return  nil;
    else return [NSString stringWithFormat:@"%@g%@g%@",sid,ssid,channel];
}

-(void) prepareCoverWithCallbackBlock:(void (^)(NSImage*))block
{
    if (picture == nil) {
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:largePictureLocation]
                                                 cachePolicy:NSURLCacheStorageAllowed
                                             timeoutInterval:5.0];
        
        [NSURLConnection sendAsynchronousRequest:request
                                           queue:[NSOperationQueue mainQueue]
                               completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
                                   picture = [[NSImage alloc] initWithData:d];
                                   if (picture) {
                                       if(block) block(picture);
                                   }
                                   else {
                                       picture = [NSImage imageNamed:@"albumfail"];
                                       if(block)block(picture);
                                   }
                               }];
    }
    else{
        if(block) block(picture);
    }
}

-(void)synchronousStop
{
    DMLog(@"%@ movie.rate = %lf",NSStringFromSelector(_cmd),movie.rate);
    if(movie.rate == 0.0)
       return;
    else {
        if(timer){
            [self invalidateTimer];
            
        }
        
        while (movie.volume>0) {
            movie.volume -= 0.1;
            [NSThread sleepForTimeInterval:0.1];
        }
        
        [movie invalidate];
    }
}

@end
