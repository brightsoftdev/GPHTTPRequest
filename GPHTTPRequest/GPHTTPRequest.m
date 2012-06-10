//
//  GPHTTPRequest.m
//  GPHTTPRequest
//
//  Created by Austin Cherry on 6/8/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "GPHTTPRequest.h"

@interface  GPHTTPRequest()

-(NSMutableURLRequest*)setupRequest;
-(void)setupPost:(NSMutableURLRequest*)request;
-(NSString*)postString;
-(NSString*)encodeString:(NSString*)string;

@end

@implementation GPHTTPRequest

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
@synthesize requestType = requestType;
@synthesize delegate = delegate;
@synthesize URL = URL;
@synthesize statusCode = statusCode;
@synthesize allowCompression = allowCompression;
@synthesize timeout = timeout;
@synthesize stringEncoding = stringEncoding;
@synthesize postValues = postValues;

static NSString* DefaultUserAgent = @"";
static NSInteger DefaultTimeout = 10; 

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(NSMutableURLRequest*)setupRequest
{
    isFinished = NO;
    if(!receivedData)
        receivedData = [[NSMutableData data] retain];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.URL
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:self.timeout];
    

    if(self.allowCompression)
        [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    
    for(NSString* key in requestHeaders)
        [request setValue:[requestHeaders objectForKey:key] forHTTPHeaderField:key];
    
    if(requestType == GPHTTPRequestHEAD)
        [request setHTTPMethod:@"HEAD"];
    else if(requestType == GPHTTPRequestDELETE)
        [request setHTTPMethod:@"DELETE"];
    else if(requestType == GPHTTPRequestPOST)
    {
        [request setHTTPMethod:@"POST"];
        [self setupPost:request];
    }
    else if(requestType == GPHTTPRequestPUT)
        [request setHTTPMethod:@"PUT"];
    
    [requestHeaders removeAllObjects];
    return request;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)startAsync
{
    NSMutableURLRequest* request = [self setupRequest];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    [connection release];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//I STRONGLY recommend you do not use it
-(void)startSync
{
    [self startAsync];
    while (!isFinished) 
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)addRequestHeader:(NSString*)value key:(NSString*)key
{
    if(!requestHeaders)
        requestHeaders = [[NSMutableDictionary alloc] init];
    [requestHeaders setValue:value forKey:key];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [receivedData setLength:0];
    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
    statusCode = [httpResponse statusCode];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [receivedData appendData:data];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    isFinished = YES;
    if([self.delegate respondsToSelector:@selector(requestFinished:)])
        [self.delegate requestFinished:self];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    isFinished = YES;
    if([self.delegate respondsToSelector:@selector(requestFailed:)])
        [self.delegate requestFailed:self];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//post and put method
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)setupPost:(NSMutableURLRequest*)request
{
    NSString *charset = (NSString *)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(self.stringEncoding));
    [self addRequestHeader:[NSString stringWithFormat:@"application/x-www-form-urlencoded; charset=%@",charset] key:@"Content-Type"];
    [request setHTTPBody:[[self postString] dataUsingEncoding:self.stringEncoding]];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)addPostValue:(id)value key:(NSString*)key
{
    if(requestType != GPHTTPRequestPUT)
        requestType = GPHTTPRequestPOST;
    
    if(!postValues)
        postValues = [[NSMutableDictionary alloc] init];
    [postValues setObject:value forKey:key];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//convert the post parameters into the need post string
-(NSString*)postString
{
    NSMutableArray* comps = [NSMutableArray array];
    for(NSString* key in postValues)
    {
        id value = [postValues objectForKey:key];
        if([value isKindOfClass:[NSArray class]])
        {
            for(NSString* nestedString in value)
                [comps addObject:[NSString stringWithFormat:@"%@[]=%@",key,[self encodeString:nestedString]]];
        }
        else if([value isKindOfClass:[NSArray class]])
        {
            for(NSString* nestedKey in value)
                [comps addObject:[NSString stringWithFormat:@"%@[%@]=%@",key,nestedKey,[self encodeString:[value objectForKey:nestedKey]]]];
        }
        else
            [comps addObject:[NSString stringWithFormat:@"%@=%@",key,[self encodeString:[postValues objectForKey:key]]]];
    }
    return [comps componentsJoinedByString:@"&"];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(NSString*)encodeString:(NSString*)string
{
    NSString * encodedURL = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                                (CFStringRef)string,
                                                                                NULL,
                                                                                (CFStringRef)@"!*'\"();:@&=+$,/?%#[] ",
                                                                                kCFStringEncodingUTF8 );
    return [encodedURL autorelease];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//request response
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//call this for text base responses (like JSON,XML,HTML,etc)
-(NSString*)responseString
{
    return [[[NSString alloc] initWithBytes:[receivedData bytes] length:[receivedData length] encoding:self.stringEncoding] autorelease];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//call this from binary responses (like images)
-(NSData*)responseData
{
    return receivedData;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)dealloc
{
    self.URL = nil;
    self.delegate = nil;
    [receivedData release];
    [requestHeaders release];
    [postValues release];
    [super dealloc];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//public factory methods
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(GPHTTPRequest*)requestWithString:(NSString*)string
{
    return [GPHTTPRequest requestWithURL:[NSURL URLWithString:string]];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(GPHTTPRequest*)requestWithURL:(NSURL*)URL
{
    GPHTTPRequest* request = [[[GPHTTPRequest alloc] init] autorelease];
    request.requestType = GPHTTPRequestGET;
    request.URL = URL;
    request.allowCompression = YES;
    request.timeout = DefaultTimeout;
    request.stringEncoding = NSUTF8StringEncoding;
    return request;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//set defaults
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(void)setDefaultTimeout:(NSInteger)timeout
{
    DefaultTimeout = timeout;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(void)setDefaultUserAgent:(NSString*)string
{
    [DefaultUserAgent release];
    DefaultUserAgent = [string retain];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
@end
