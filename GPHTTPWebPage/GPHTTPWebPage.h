//
//  GPHTTPWebPage.h
//  GPHTTPRequest
//
//  Created by Austin Cherry on 7/5/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GPHTTPRequest.h"

@class GPHTTPWebPage;

@protocol GPHTTPWebPageDelegate <NSObject>

@optional
//notifies when a request finishes
-(void)webPageFinished:(GPHTTPWebPage*)request;
-(void)webPageFailed:(GPHTTPWebPage*)request;

@end

@interface GPHTTPWebPage : NSObject
{
    GPHTTPRequest* mainRequest;
    NSOperationQueue* requestQueue;
    NSString* HTMLContent;
    NSURL* URL;
    NSInteger statusCode;
    id<GPHTTPWebPageDelegate>delegate;
    #if NS_BLOCKS_AVAILABLE
    GPHTTPBlock completionBlock;
    GPHTTPBlock failureBlock;
    #endif
    #if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
    BOOL continueInBackground;
    UIBackgroundTaskIdentifier backgroundTask;
    #endif
}


@property(nonatomic,retain)NSURL* URL;
@property(nonatomic,assign,readonly)NSInteger statusCode;
@property(nonatomic,assign)id<GPHTTPWebPageDelegate>delegate;
#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
@property(nonatomic,assign)BOOL continueInBackground;
#endif


/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//init
-(id)initWithURL:(NSURL*)url;
-(id)initWithString:(NSString*)string;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//modify/start request
-(void)startSync;
-(void)startAsync;
#if NS_BLOCKS_AVAILABLE
-(void)setFinishBlock:(GPHTTPBlock)completeBlock;
-(void)setFailedBlock:(GPHTTPBlock)failBlock;
#endif
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//load request from disk
+(NSURL*)pathForSite:(NSString*)urlString;
+(NSString*)docsDirectory;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//public factory methods
+(GPHTTPWebPage*)requestWithURL:(NSURL*)URL;
+(GPHTTPWebPage*)requestWithString:(NSString*)string;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////


@end
