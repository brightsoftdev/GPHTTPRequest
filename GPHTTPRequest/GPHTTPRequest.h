//
//  GPHTTPRequest.h
//  GPHTTPRequest
//
//  Created by Austin Cherry on 6/8/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
#import <UIKit/UIKit.h> // Necessary for background task support
#endif

typedef enum{
    GPHTTPRequestGET,
    GPHTTPRequestDELETE,
    GPHTTPRequestHEAD,
    GPHTTPRequestPOST,
    GPHTTPRequestPUT,
}GPHTTPRequestType;

typedef enum{
    GPHTTPCacheIfModifed, //ask server for did modify
    GPHTTPCacheCustomTime, //use custom timeout, this will be set, if you add a custom timeout
    GPHTTPUseCacheAndUpdate, //load from cache then update request
    GPHTTPJustUseCache, //don't send request and just use cache
    GPHTTPIgnoreCache //ignore cache completely
}GPHTTPRequestCache;

#if NS_BLOCKS_AVAILABLE
typedef void (^GPHTTPBlock)(void);
#endif

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//delegate
@class GPHTTPRequest;

@protocol GPHTTPRequestDelegate <NSObject>

@optional
//notifies when a request finishes
-(void)requestFinished:(GPHTTPRequest*)request;
-(void)requestFailed:(GPHTTPRequest*)request;
-(void)setProgress:(float)progress;

@end

@interface GPHTTPRequest : NSOperation<GPHTTPRequestDelegate>
{
    NSURLConnection *connection;
    NSMutableData* receivedData;
    GPHTTPRequestType requestType;
    NSURL* URL;
    NSInteger statusCode;
    id<GPHTTPRequestDelegate>delegate;
    BOOL allowCompression;
    NSInteger timeout;
    NSMutableDictionary* requestHeaders;
    NSStringEncoding stringEncoding;
    BOOL isFinished;
    BOOL isExecuting;
    NSMutableDictionary* postValues;
    NSMutableArray* postFiles;
    GPHTTPRequestCache cacheModel;
    BOOL didUseCache;
    NSInteger cacheTimeout;
    NSDate* lastModified;
    NSDate* expiresDate;
    BOOL trackProgress;
    unsigned long long contentLength;
    unsigned long long progessLength;
    #if NS_BLOCKS_AVAILABLE
    GPHTTPBlock completionBlock;
    GPHTTPBlock failureBlock;
    #endif
    #if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
    BOOL continueInBackground;
    UIBackgroundTaskIdentifier backgroundTask;
    #endif
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//properties
@property(nonatomic,assign)GPHTTPRequestType requestType;
@property(nonatomic,retain)NSURL* URL;
@property(nonatomic,assign,readonly)NSInteger statusCode;
@property(nonatomic,assign)id<GPHTTPRequestDelegate>delegate;
@property(nonatomic,assign)BOOL allowCompression;
@property(nonatomic,assign)NSInteger timeout;
@property(nonatomic,assign)NSStringEncoding stringEncoding;
@property(nonatomic,retain,readonly)NSDictionary* postValues;
@property(nonatomic,retain,readonly)NSArray* postFiles;
@property(nonatomic,assign)GPHTTPRequestCache cacheModel;
@property(nonatomic,assign)NSInteger cacheTimeout;
@property(nonatomic,assign)BOOL trackProgress;
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
-(void)addRequestHeader:(NSString*)value key:(NSString*)key;
#if NS_BLOCKS_AVAILABLE
-(void)setFinishBlock:(GPHTTPBlock)completeBlock;
-(void)setFailedBlock:(GPHTTPBlock)failBlock;
#endif
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//POST/PUT methods
-(void)addPostValue:(id)value key:(NSString*)key;
-(void)addPostData:(NSData*)data mimeType:(NSString*)mimeType fileName:(NSString*)name forKey:(NSString*)key;
-(void)addPostFile:(NSURL*)path forKey:(NSString*)key;
-(void)addPostFile:(NSURL*)path fileName:(NSString*)name forKey:(NSString*)key;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//request finished
-(NSString*)responseString;
-(NSData*)responseData;
-(unsigned long long)responseLength;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//caching functions
-(BOOL)didLoadFromCache;
-(void)setCacheTimeout:(NSInteger)seconds;
+(NSString*)cacheDirectory;
+(NSString *)keyForURL:(NSURL*)url;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//public factory methods
+(GPHTTPRequest*)requestWithURL:(NSURL*)URL;
+(GPHTTPRequest*)requestWithString:(NSString*)string;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//set defaults
+(void)setDefaultTimeout:(NSInteger)timeout;
+(void)setDefaultUserAgent:(NSString*)string;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
@end
