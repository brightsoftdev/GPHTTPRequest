//
//  GPHTTPWebPage.m
//  GPHTTPRequest
//
//  Created by Austin Cherry on 7/5/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "GPHTTPWebPage.h"
#import <libxml2/libxml/HTMLparser.h>

@implementation GPHTTPWebPage

@synthesize delegate = delegate;
@synthesize URL = URL;
@synthesize statusCode = statusCode;
#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
@synthesize continueInBackground = continueInBackground;
#endif

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(id)initWithURL:(NSURL*)url
{
    if(self = [super init])
    {
        self.URL = url;
    }
    return self;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(id)initWithString:(NSString*)string
{
    return [[GPHTTPWebPage alloc] initWithURL:[NSURL URLWithString:string]];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)startAsync
{
    [mainRequest release];
    mainRequest = [[GPHTTPRequest requestWithURL:self.URL] retain];
    [mainRequest setCompletionBlock:^{
        [self ParseHTML:[mainRequest responseString]];
    }];
    mainRequest.continueInBackground = self.continueInBackground;
    [mainRequest startAsync];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//Better if you can use async request instead
-(void)startSync
{
    GPHTTPRequest* request = [[GPHTTPRequest requestWithURL:self.URL] retain];
    [request startSync];
    [self ParseHTML:[request responseString]];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)cancel
{
    [mainRequest cancel];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//returns if the last error if the connection failed. nil if no error
-(NSError*)error
{
    return [mainRequest error];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//block based request
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if NS_BLOCKS_AVAILABLE
-(void)setFinishBlock:(GPHTTPBlock)completeBlock
{
    [completionBlock release];
	completionBlock = [completeBlock copy];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)setFailedBlock:(GPHTTPBlock)failBlock
{
    [failureBlock release];
	failureBlock = [failBlock copy];
}
#endif


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)ParseHTML:(NSString*)response
{
    CFStringEncoding cfenc = CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding);
    CFStringRef cfencstr = CFStringConvertEncodingToIANACharSetName(cfenc);
    const char *enc = CFStringGetCStringPtr(cfencstr, 0);
    
    HTMLContent = @"";
    htmlSAXHandler saxHandler;
    memset( &saxHandler, 0, sizeof(saxHandler) );
    saxHandler.startElement = &elementDidStart;
    saxHandler.endElement = &elementDidEnd;
    saxHandler.characters = &foundChars;
    saxHandler.endDocument = &documentDidEnd;
    saxHandler.error = &error;
    htmlDocPtr _doc = htmlSAXParseDoc((xmlChar*)[response UTF8String],enc,&saxHandler,(__bridge void*)self);
    //xmlCleanupParser();
    free(_doc);
}
///////////////////////////////////////////////////////////////////////////////////////////////////


///////////////////////////////////////////////////////////////////////////////////////////////////
//private
///////////////////////////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////////////////////////
//c functions that forward to objective c functions
///////////////////////////////////////////////////////////////////////////////////////////////////
void elementDidStart(void *ctx,const xmlChar *name,const xmlChar **atts)
{
    NSString* elementName = [NSString stringWithCString:(const char*)name encoding:NSUTF8StringEncoding];
    NSMutableDictionary* collect = nil;
    
    if(atts)
    {
        const xmlChar *attrib = NULL;
        collect = [NSMutableDictionary dictionary];
        int i = 0;
        NSString* key = @"";
        do
        {
            attrib = *atts;
            if(!attrib)
                break;
            if(i % 2 != 0 && i != 0)
            {
                NSString* val = [NSString stringWithCString:(const char*)attrib encoding:NSUTF8StringEncoding];
                [collect setObject:val forKey:key];
            }
            else
                key = [NSString stringWithCString:(const char*)attrib encoding:NSUTF8StringEncoding];
            atts++;
            i++;
        }while(attrib != NULL);
    }
    
    NSString* tag = [elementName lowercaseString];
    //NSLog(@"collect: %@",collect);
    HTMLParser* parser = (HTMLParser*)ctx;
    [parser didStartElement:tag attributes:collect];
}
///////////////////////////////////////////////////////////////////////////////////////////////////
void foundChars(void *ctx,const xmlChar *ch,int len)
{
    NSString* string = [NSString stringWithCString:(const char*)ch encoding:NSUTF8StringEncoding];
    HTMLParser* parser = (HTMLParser*)ctx;
    [parser foundCharacters:string];
}
///////////////////////////////////////////////////////////////////////////////////////////////////
void elementDidEnd(void *ctx,const xmlChar *name)
{
    NSString* elementName = [NSString stringWithCString:(const char*)name encoding:NSUTF8StringEncoding];
    NSString* tag = [elementName lowercaseString];
    HTMLParser* parser = (HTMLParser*)ctx;
    [parser didEndElement:tag];
}
///////////////////////////////////////////////////////////////////////////////////////////////////
void documentDidEnd(void *ctx)
{
    HTMLParser* parser = (HTMLParser*)ctx;
    [parser documentDidEnd];
}
///////////////////////////////////////////////////////////////////////////////////////////////////
void error( void * ctx, const char * msg, ... )
{
    //va_list args;
    //va_start(args, msg);
    //NSString *retVal = [[[NSString alloc] initWithFormat:[NSString stringWithCString:msg encoding:NSUTF8StringEncoding] arguments:args] autorelease];
    //va_end(args);
    // NSLog(@"Got an error: %@ ",retVal);
}
///////////////////////////////////////////////////////////////////////////////////////////////////
//objective c function from c functions above
///////////////////////////////////////////////////////////////////////////////////////////////////
-(void)didStartElement:(NSString*)tag attributes:(NSDictionary*)attributeDict
{
    //NSLog(@"tag did start name: %@",tag);
    if([tag isEqualToString:@"meta"] || [tag isEqualToString:@"link"] ||  [tag isEqualToString:@"img"])
        if(attributeDict)
        {
            //NSLog(@"attributes: %@",attributeDict);
            //modify HTML string and send request to download to local directory
            NSString* attribString = @"";
            for(NSString* key in attributeDict)
            {
                NSString* value = [attributeDict objectForKey:key];
                value = [value lowercaseString];
                if([key isEqualToString:@"src"] || [key isEqualToString:@"href"])
                {
                    if([value rangeOfString:@"http"].location == NSNotFound)
                        value = [NSString stringWithFormat:@"%@%@",mainRequest,value];
                    NSString* urlString = value;
                    NSRange range = [value rangeOfString:@"/" options:NSBackwardsSearch];
                    if(range.location != NSNotFound)
                    {
                        if(!requestQueue)
                        {
                            requestQueue = [[NSOperationQueue alloc] init];
                            requestQueue.maxConcurrentOperationCount = 4;
                        }
                        __block NSString* diskPath = [value substringFromIndex:range.location+1];
                        GPHTTPRequest* request = [GPHTTPRequest requestWithString:urlString];
                        request.continueInBackground = self.continueInBackground;
                        [request setCompletionBlock:^{
                            [self writeToDisk:diskPath data:[request responseData]];
                        }];
                        request.cacheModel = GPHTTPIgnoreCache;
                        [requestQueue addOperation:request];
                        //NSLog(@"value: %@",diskPath);
                    }
                }
                attribString = [attribString stringByAppendingFormat:@"%@=\"%@\" ",key, value];
            }
            HTMLContent = [HTMLContent stringByAppendingFormat:@"<%@ %@>",tag,attribString];
        }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
-(void)foundCharacters:(NSString*)string
{
    //NSLog(@"string: Text: %@",string);
    if(string)
        HTMLContent = [HTMLContent stringByAppendingFormat:@"%@",string];
}
///////////////////////////////////////////////////////////////////////////////////////////////////
-(void)didEndElement:(NSString*)tag
{
    //NSLog(@"tag did end name: %@",tag);
    HTMLContent = [HTMLContent stringByAppendingFormat:@"</%@>",tag];
}
///////////////////////////////////////////////////////////////////////////////////////////////////
-(void)documentDidEnd
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    //make a file name to write the data to using the documents directory:
    NSString* file = self.URL;
    if([file rangeOfString:@"."].location == NSNotFound)
        file = [file stringByAppendingFormat:@".html"];
    
    NSString *fileName = [NSString stringWithFormat:@"%@/%@",documentsDirectory,file];
    NSURL* url = [NSURL fileURLWithPath:fileName];
    [HTMLContent writeToFile:fileName atomically:NO encoding:NSUTF8StringEncoding error:nil];
}
///////////////////////////////////////////////////////////////////////////////////////////////////
-(void)writeToDisk:(NSString*)name data:(NSData*)data
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"%@/%@",documentsDirectory,name];
    [data writeToFile:fileName atomically:NO encoding:NSUTF8StringEncoding error:nil];
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)dealloc
{
    [mainRequest release];
    [requestQueue release];
    [super dealloc];
}
///////////////////////////////////////////////////////////////////////////////////////////////////
+(NSURL*)pathForSite:(NSString*)urlString
{
    NSString* file = self.URL;
    if([file rangeOfString:@"."].location == NSNotFound)
        file = [file stringByAppendingFormat:@".html"];
    
    NSString *fileName = [NSString stringWithFormat:@"%@/%@",documentsDirectory,file];
    return [NSURL fileURLWithPath:fileName];
}
///////////////////////////////////////////////////////////////////////////////////////////////////

@end
