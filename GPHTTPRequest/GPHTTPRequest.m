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

static NSString* DefaultUserAgent = @"";
static NSInteger DefaultTimeout = 10; 

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(id)initWithURL:(NSURL*)url
{
    if(self = [super init])
    {
        self.requestType = GPHTTPRequestGET;
        self.URL = URL;
        self.allowCompression = YES;
        self.timeout = DefaultTimeout;
        self.stringEncoding = NSUTF8StringEncoding;
        self.cacheModel = GPHTTPCacheIfModifed;
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
        NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
        [connection release];
    }
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
    [lastModified release];
    if ([response isKindOfClass:[NSHTTPURLResponse self]]) 
    {
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
        statusCode = [httpResponse statusCode];
		NSDictionary *headers = [httpResponse allHeaderFields];
		NSString *modified = [headers objectForKey:@"Last-Modified"];
		if (modified) 
        {
			NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
			//avoid problem if the user's locale is incompatible with HTTP-style dates
			[dateFormatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
            
			[dateFormatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss zzz"];
			lastModified = [[dateFormatter dateFromString:modified] retain];
			[dateFormatter release];
		}
		else
			lastModified = [[NSDate dateWithTimeIntervalSinceReferenceDate:0] retain];
	}
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

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* dataPath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"GPHTTPRequestCache"];
    
	if (![[NSFileManager defaultManager] fileExistsAtPath:dataPath])
    {
        [[NSFileManager defaultManager] createDirectoryAtPath:dataPath
                                  withIntermediateDirectories:NO
                                                   attributes:nil
                                                        error:nil];
    }
    NSString* checkPath = [dataPath stringByAppendingFormat:@"/%@",[GPHTTPRequest keyForURL:self.URL]];
    if([[NSFileManager defaultManager] fileExistsAtPath:checkPath])
    {
        [receivedData setLength:0];
        [receivedData appendData:[[NSFileManager defaultManager] contentsAtPath:checkPath]];
        if([self.delegate respondsToSelector:@selector(requestFinished:)])
            [self.delegate requestFinished:self];
        if(cacheModel == GPHTTPUseCacheAndUpdate)
        {
            isFinished = YES;
            return NO;
        }
        return YES;
    }
    return NO;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
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
    [postFiles release];
    [lastModified release];
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
