//
//  PMDReachabilityWrapper.m
//  privMD
//
//  Created by Surender Rathore on 16/04/14.
//  Copyright (c) 2014 Rahul Sharma. All rights reserved.
//

#import "PMDReachabilityWrapper.h"
#import "Reachability.h"
#import <UIKit/UIKit.h>


@interface PMDReachabilityWrapper ()

@property (nonatomic, strong) Reachability *hostReach;
@property (nonatomic, strong) Reachability *internetReach;
@property (nonatomic, strong) Reachability *wifiReach;
@property (nonatomic, assign) int fireSelectorOnce;
@end

@implementation PMDReachabilityWrapper
@synthesize hostReach;
@synthesize internetReach;
@synthesize wifiReach;
@synthesize target;
@synthesize selector;

static PMDReachabilityWrapper *reachabilityWrapper = nil;


+(instancetype)sharedInstance
{
    if (!reachabilityWrapper) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            reachabilityWrapper = [[self alloc] init];
        });
    }
    
    return reachabilityWrapper;
}


#pragma Reachability

- (BOOL)isNetworkAvailable {
    
    if (_networkStatus != NotReachable) {
        return YES;
    }
    return NO;
}

// Called by Reachability whenever status changes.
- (void)reachabilityChanged:(NSNotification* )note {
    

    
    Reachability *curReach = (Reachability *)[note object];
    
    NSParameterAssert([curReach isKindOfClass: [Reachability class]]);
    
    _networkStatus = [curReach currentReachabilityStatus];
    UILabel *label;
    UIView *topView;
    if (_networkStatus == NotReachable) {
        
        NSLog(@"Network not reachable.");
        
        
        
        [label setHidden:NO];
        
         if ([[UIScreen mainScreen] bounds].size.height >= 812)
         {
              label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0,[[[UIApplication sharedApplication]delegate] window].frame.size.width,88 )];
         }else{
             label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0,[[[UIApplication sharedApplication]delegate] window].frame.size.width,64 )];
         }
       
        
        label.text = @"No Network Connection";
        label.font = [UIFont fontWithName:@"OpenSans-Bold" size:12];
        label.textColor = [UIColor whiteColor];
        label.backgroundColor = [UIColor redColor];
        [label setUserInteractionEnabled: false];
        // label.layer.cornerRadius = 5;
        // label.tag = 400;
        // label.clipsToBounds = YES;
        label.textAlignment = NSTextAlignmentCenter;
        UIWindow *window = [[[UIApplication sharedApplication]delegate] window];
        for (UIView *subView in [window subviews]) {
            if ([subView isKindOfClass:[UILabel class]]) {
                [subView removeFromSuperview];
            }
        }
        [window addSubview:label];

        _fireSelectorOnce = 0;
    }
    else {
        NSLog(@"Network Reachable");
    
            UIWindow *window = [[[UIApplication sharedApplication]delegate] window];
            for (UIView *subView in [window subviews]) {
                if ([subView isKindOfClass:[UILabel class]]) {
                    [subView removeFromSuperview];
                }
            

       
        }

        if ([target respondsToSelector:selector]) {
            if (_fireSelectorOnce == 0) {
                [target performSelector:selector withObject:nil afterDelay:1];
                _fireSelectorOnce = 1;
            }
            
        }
        
    }
    
}
- (void)monitorReachability {
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];
    
    self.hostReach = [Reachability reachabilityWithHostName:@"www.google.com"];
    [self.hostReach startNotifier];
    
    self.internetReach = [Reachability reachabilityForInternetConnection];
    [self.internetReach startNotifier];
    
    self.wifiReach = [Reachability reachabilityForLocalWiFi];
    [self.wifiReach startNotifier];
}

@end
