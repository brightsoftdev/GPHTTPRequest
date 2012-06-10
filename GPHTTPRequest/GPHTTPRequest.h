//
//  GPHTTPRequest.h
//  GPHTTPRequest
//
//  Created by Austin Cherry on 6/8/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum{
    GPHTTPRequestGET,
    GPHTTPRequestDELETE,
    GPHTTPRequestHEAD,
    GPHTTPRequestPOST,
    GPHTTPRequestPUT,
}GPHTTPRequestType;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//delegate
@class GPHTTPRequest;

@protocol GPHTTPRequestDelegate <NSObject>

@optional
//notifies when a request finishes
-(void)requestFinished:(GPHTTPRequest*)request;
-(void)requestFailed:(GPHTTPRequest*)request;

@end

@interface GPHTTPRequest : NSObject
{
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
    NSMutableDictionary* postValues;
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

-(void)startSync;
-(void)startAsync;
-(void)addRequestHeader:(NSString*)value key:(NSString*)key;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//POST/PUT methods
-(void)addPostValue:(id)value key:(NSString*)key;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//request finished
-(NSString*)responseString;
-(NSData*)responseData;

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
