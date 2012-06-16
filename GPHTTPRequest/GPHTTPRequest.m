//
//  GPHTTPRequest.m
//  GPHTTPRequest
//
//  Created by Austin Cherry on 6/8/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "GPHTTPRequest.h"
#import <CommonCrypto/CommonHMAC.h>

@interface  GPHTTPRequest()

-(NSMutableURLRequest*)setupRequest;
-(void)setupPost:(NSMutableURLRequest*)request;
-(void)setupPut:(NSMutableURLRequest*)request;
-(NSString*)postString;
-(NSString*)putString:(NSString*)stringBoundary;
-(NSString*)encodeString:(NSString*)string;

-(NSDate*)httpDateFormat:(NSString*)string;
-(void)finishWithCache:(NSString*)checkPath;
-(NSDictionary*)fileModifyDate:(NSString*)path;
-(void)updateProgess;
-(void)startTracking:(BOOL)sync;

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
@synthesize postFiles = postFiles;
@synthesize cacheModel = cacheModel;
@synthesize cacheTimeout = cacheTimeout;
@synthesize trackProgress = trackProgress;

static NSString* DefaultUserAgent = @"";
static NSInteger DefaultTimeout = 10; 

static NSString *GPHTTPRequestRunLoopMode = @"GPHTTPRequestRunLoopMode";
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(id)initWithURL:(NSURL*)url
{
    if(self = [super init])
    {
        self.requestType = GPHTTPRequestGET;
        self.URL = url;
        self.allowCompression = YES;
        self.timeout = DefaultTimeout;
        self.stringEncoding = NSUTF8StringEncoding;
        self.cacheModel = GPHTTPCacheIfModifed;
        cacheTimeout = 0;
        isExecuting = NO;
        isFinished = NO;
        contentLength = 0;
    }
    return self;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(id)initWithString:(NSString*)string
{
    return [[GPHTTPRequest alloc] initWithURL:[NSURL URLWithString:string]];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(NSMutableURLRequest*)setupRequest
{
    isFinished = NO;
    if(!receivedData)
        receivedData = [[NSMutableData data] retain];
    
    if([self checkCache])
    {
        isFinished = YES;
        [self finish];
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.URL
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
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
    {
        [request setHTTPMethod:@"PUT"];
        [self setupPut:request];
    }
    
    [requestHeaders removeAllObjects];
    return request;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)startAsync
{
    NSMutableURLRequest* request = [self setupRequest];
    if(request)
    {
        if(self.trackProgress && progessLength == 0)
        {
            [self startTracking:NO];
            return;
        }
        NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
        [connection release];
    }
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//Better if you can use async request instead
-(void)startSync
{
    if(self.trackProgress)
        [self startTracking:YES];
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
    [lastModified release];
    [expiresDate release];
    if ([response isKindOfClass:[NSHTTPURLResponse self]]) 
    {
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
        statusCode = [httpResponse statusCode];
        NSDictionary *headers = [httpResponse allHeaderFields];
        //NSLog(@"headers: %@",headers);

        contentLength = [[headers objectForKey:@"Content-Length"] longLongValue];
        if(contentLength == 0)
            contentLength = -1;
        NSString *modified = [headers objectForKey:@"Last-Modified"];
        NSString* expire = [headers objectForKey:@"Expires"];
            NSDate* date = nil;
        if(expire)
            date = [self httpDateFormat:expire];
        if(date)
            expiresDate = [date retain];
        else if([headers objectForKey:@"Cache-Control"])
        {
            NSString* cache = [headers objectForKey:@"Cache-Control"];
            int age = 0;
            NSRange range = [cache rangeOfString:@"max-age="];
            if(range.location != NSNotFound)
            {
                NSRange end = [cache rangeOfString:@","];
                if(end.location == NSNotFound)
                    end.location = cache.length;
                int start = range.location + range.length;
                age = [[cache substringWithRange:NSMakeRange(start, end.location-start)] intValue];
            }
            expiresDate = [[NSDate dateWithTimeIntervalSinceNow:age] retain];
        }
        else if (modified) 
            lastModified = [[self httpDateFormat:modified] retain];
	}
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(NSDate*)httpDateFormat:(NSString*)string
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    //avoid problem if the user's locale is incompatible with HTTP-style dates
    [dateFormatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    
    [dateFormatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss zzz"];
    NSDate* date = [dateFormatter dateFromString:string];
    [dateFormatter release];
    return date;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [receivedData appendData:data];
    [self updateProgess];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self finish];
    if(cacheModel != GPHTTPIgnoreCache && requestType == GPHTTPRequestGET)
        [self writeCache];
    if([self.delegate respondsToSelector:@selector(requestFinished:)])
        [self.delegate requestFinished:self];
    //[connection release];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    isFinished = YES;
    [self finish];
    if([self.delegate respondsToSelector:@selector(requestFailed:)])
        [self.delegate requestFailed:self];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (NSCachedURLResponse *) connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return nil;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//caching functions
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//returns if request was loaded from cache
-(BOOL)didLoadFromCache
{
    return didUseCache;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//set the request cache Time to live.
-(void)setCacheTimeout:(NSInteger)seconds
{
    self.cacheModel = GPHTTPCacheCustomTime;
    cacheTimeout = seconds;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//check and see if there is a request to use in the cache
-(BOOL)checkCache
{
    if(cacheModel == GPHTTPIgnoreCache)
        return NO;
    NSURLCache *sharedCache = [[NSURLCache alloc] initWithMemoryCapacity:0
                                                            diskCapacity:0
                                                                diskPath:nil];
    [NSURLCache setSharedURLCache:sharedCache];
    [sharedCache release];

    NSString* dataPath = [GPHTTPRequest cacheDirectory];
    NSString* checkPath = [dataPath stringByAppendingFormat:@"/%@",[GPHTTPRequest keyForURL:self.URL]];
    if(cacheModel != GPHTTPIgnoreCache)
    {        
        if([[NSFileManager defaultManager] fileExistsAtPath:checkPath])
        {
            if(cacheModel == GPHTTPUseCacheAndUpdate || cacheModel == GPHTTPJustUseCache)
            {
                [self finishWithCache:checkPath];
                if(cacheModel == GPHTTPJustUseCache)
                    return YES;
                return NO;
            }
            
            NSDictionary* attribs = [self fileModifyDate:checkPath];
            //NSLog(@"attribs: %@",attribs);
            NSDate* date = [attribs fileCreationDate];
            
            NSDate* expires = [attribs fileModificationDate];
            if(!date)
                return NO;
            
            BOOL doCache = NO;
            if(cacheModel == GPHTTPCacheIfModifed)
            {
                NSDate* constDate = [[[NSDate alloc] initWithTimeIntervalSince1970:30] autorelease];
                NSDate* now = [NSDate date];
                NSComparisonResult result = [now compare:date];
                if(result  == NSOrderedDescending && ![date isEqualToDate:constDate])
                    doCache = YES;
                
                result = [now compare:expires];
                if(result  == NSOrderedAscending)
                    doCache = YES;
                else
                    return NO;
            }
            else
            {
                NSTimeInterval fileCache = fabs([expires timeIntervalSinceNow]);
                NSTimeInterval time = self.cacheTimeout;
                if(fileCache < time)
                    doCache = YES;
            }
            
            if(doCache)
            {
                [self finishWithCache:checkPath];
                return YES;
            }
        }
    }
    return NO;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//complete request with cache
-(void)finishWithCache:(NSString*)path
{
    didUseCache = YES;
    isFinished = YES;
    [receivedData setLength:0];
    [receivedData appendData:[[NSFileManager defaultManager] contentsAtPath:path]];
    if([self.delegate respondsToSelector:@selector(requestFinished:)])
        [self.delegate requestFinished:self];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//MD5 hash of URL
+ (NSString *)keyForURL:(NSURL*)url
{
	NSString *urlString = [url absoluteString];
	if ([urlString length] == 0) {
		return nil;
	}
    
	// Strip trailing slashes
	if ([[urlString substringFromIndex:[urlString length]-1] isEqualToString:@"/"])
		urlString = [urlString substringToIndex:[urlString length]-1];
    
	// Borrowed from: http://stackoverflow.com/questions/652300/using-md5-hash-on-a-string-in-cocoa
	const char *cStr = [urlString UTF8String];
	unsigned char result[16];
	CC_MD5(cStr, (CC_LONG)strlen(cStr), result);
	return [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",result[0], result[1], result[2], result[3], result[4], result[5], result[6], result[7],result[8], result[9], result[10], result[11],result[12], result[13], result[14], result[15]]; 	
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//the cacheDirectory on disk
+(NSString*)cacheDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* dataPath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"GPHTTPRequestCache"];
    
	if (![[NSFileManager defaultManager] fileExistsAtPath:dataPath])
    {
        [[NSFileManager defaultManager] createDirectoryAtPath:dataPath
                                  withIntermediateDirectories:NO
                                                   attributes:nil
                                                        error:nil];
    }
    return dataPath;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//write to cache directory
-(void)writeCache
{
    NSString* dataPath = [GPHTTPRequest cacheDirectory];
    NSString* checkPath = [dataPath stringByAppendingFormat:@"/%@",[GPHTTPRequest keyForURL:self.URL]];
    [receivedData writeToURL:[NSURL fileURLWithPath:checkPath] atomically:NO];
    if(cacheModel == GPHTTPCacheIfModifed)
    {
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        if(lastModified)
            [dict setObject:lastModified forKey:NSFileCreationDate];
        if(expiresDate)
            [dict setObject:expiresDate forKey:NSFileModificationDate];
        if(!lastModified)
            [dict setObject:[[[NSDate alloc] initWithTimeIntervalSince1970:30] autorelease] forKey:NSFileCreationDate];
        
        [[NSFileManager defaultManager] setAttributes:dict ofItemAtPath:checkPath error:nil];
    }
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(NSDictionary*)fileModifyDate:(NSString*)path
{
    if([[NSFileManager defaultManager] fileExistsAtPath:path])
    {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        return attributes;
    }
    return nil;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//post and put method
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(NSData*)stringAsData:(NSString*)string
{
    return [string dataUsingEncoding:self.stringEncoding];
}
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
-(void)setupPut:(NSMutableURLRequest*)request
{
	NSString *charset = (NSString *)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(self.stringEncoding));
	CFUUIDRef uuid = CFUUIDCreate(nil);
	NSString *uuidString = [(NSString*)CFUUIDCreateString(nil, uuid) autorelease];
	CFRelease(uuid);
	NSString *stringBoundary = [NSString stringWithFormat:@"0xKhTmLbOuNdArY-%@",uuidString];
    [self addRequestHeader:[NSString stringWithFormat:@"multipart/form-data; charset=%@; boundary=%@", charset, stringBoundary] key:@"Content-Type"];
    
    NSString *endItemBoundary = [NSString stringWithFormat:@"\r\n--%@\r\n",stringBoundary];
    NSString* postString = [self putString:stringBoundary];
    NSMutableData* putData = [NSMutableData data];
    
    [putData appendData:[postString dataUsingEncoding:self.stringEncoding]];
	NSInteger i = 0;
	for (NSDictionary* item in postFiles) 
    {
		[putData appendData:[self stringAsData:[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", [item objectForKey:@"key"], [item objectForKey:@"name"]]]];
		[putData appendData:[self stringAsData:[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", [item objectForKey:@"type"]]]];
        [putData appendData:[item objectForKey:@"data"]];
		i++;
		if (i != postFiles.count)// Only add the boundary if this is not the last item in the post body
			[putData appendData:[self stringAsData:endItemBoundary]];
	}
	
	[putData appendData:[self stringAsData:[NSString stringWithFormat:@"\r\n--%@--\r\n",stringBoundary]]];
    [request setHTTPBody:putData];
}
                 
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//add file data to post/put form.
-(void)addPostData:(NSData*)data mimeType:(NSString*)mimeType fileName:(NSString*)name forKey:(NSString*)key
{
    requestType = GPHTTPRequestPUT;
    if(!postFiles)
        postFiles = [[NSMutableArray alloc] init];
    NSMutableDictionary* dic = [NSMutableDictionary dictionary];
    [dic setObject:name forKey:@"name"];
    [dic setObject:data forKey:@"data"];
    [dic setObject:mimeType forKey:@"type"];
    [dic setObject:key forKey:@"key"];
    [postFiles addObject:dic];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)addPostFile:(NSURL*)path forKey:(NSString*)key
{
    [self addPostFile:path fileName:nil forKey:key];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//add a file from a url path to post/put form.
-(void)addPostFile:(NSURL*)path fileName:(NSString*)name forKey:(NSString*)key
{
    NSURLRequest* fileUrlRequest = [[NSURLRequest alloc] initWithURL:path];
    
    NSError* error = nil;
    NSURLResponse* response = nil;
    NSData* fileData = [NSURLConnection sendSynchronousRequest:fileUrlRequest returningResponse:&response error:&error];
    NSString* mimeType = [response MIMEType];
    [fileUrlRequest release];
    NSString* fileName = name;
    if(!fileName)
        fileName = [response suggestedFilename];
    
    [self addPostData:fileData mimeType:mimeType fileName:fileName forKey:key];
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
        else if([value isKindOfClass:[NSDictionary class]])
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
//convert the post parameters into the need PUT string
-(NSString*)putString:(NSString*)stringBoundary
{
    NSString* postString = [NSString stringWithFormat:@"--%@\r\n",stringBoundary];
    
    NSUInteger i=0;
    NSString *endItemBoundary = [NSString stringWithFormat:@"\r\n--%@\r\n",stringBoundary];
    for(NSString* key in postValues)
    {
        id value = [postValues objectForKey:key];
        if([value isKindOfClass:[NSArray class]])
        {
            for(NSString* nestedString in value)
                postString = [postString stringByAppendingFormat:@"Content-Disposition: form-data; name=\"%@[]\"\r\n\r\n%@",key,[self encodeString:nestedString]];
        }
        else if([value isKindOfClass:[NSDictionary class]])
        {
            for(NSString* nestedKey in value)
                postString = [postString stringByAppendingFormat:@"Content-Disposition: form-data; name=\"%@[%@]\"\r\n\r\n%@",key,nestedKey,[self encodeString:[value objectForKey:nestedKey]]];
        }
        else
            postString = [postString stringByAppendingFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@",key,[self encodeString:value]];
        
        i++;
		if (i != postValues.count || postFiles.count > 0) //Only add the boundary if this is not the last item in the post body
			postString = [postString stringByAppendingFormat:@"%@",endItemBoundary];
    }
    return postString;
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
//request progress tracking
-(void)updateProgess
{
    if(!self.trackProgress || progessLength <= 0)
        return;
    float increment = 100.0f/progessLength;
    float progress = (increment*receivedData.length);
    if(progress > 1)
        progress = 1;
    if([self.delegate respondsToSelector:@selector(setProgress:)])
        [self.delegate setProgress:progress];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)startTracking:(BOOL)sync
{
    GPHTTPRequest* request = [GPHTTPRequest requestWithURL:self.URL];
    request.requestType = GPHTTPRequestHEAD;
    if(sync)
    {
        [request startSync];
        progessLength = [request responseLength];
    }
    else
    {
        request.delegate = [self retain];
        [request startAsync];
    }
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)requestFinished:(GPHTTPRequest *)request
{
    progessLength = [request responseLength];
    [self startAsync];
    [request.delegate release];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//just forward the failed head request to our controller to let them know what happen
-(void)requestFailed:(GPHTTPRequest *)request
{
    if([self.delegate respondsToSelector:@selector(requestFailed:)])
        [self.delegate requestFailed:request];
}
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
-(unsigned long long)responseLength
{
    return contentLength;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)dealloc
{
    self.URL = nil;
    self.delegate = nil;
    [receivedData release];
    [requestHeaders release];
    [postValues release];
    [postFiles release];
    [lastModified release];
    [expiresDate release];
    [super dealloc];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//NSOperation implemention
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)start
{
    if (![NSThread isMainThread])
    {
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
        return;
    }
    
    [self willChangeValueForKey:@"isExecuting"];
    isExecuting = YES;
    [self didChangeValueForKey:@"isExecuting"];
    
    [self startAsync];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)finish
{
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    
    isExecuting = NO;
    isFinished = YES;
    
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)isConcurrent
{
    return YES;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)isFinished 
{
	return isFinished;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)isExecuting 
{
	return isExecuting;
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
    return [[[GPHTTPRequest alloc] initWithURL:URL] autorelease];
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
