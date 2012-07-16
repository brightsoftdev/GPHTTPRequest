//
//  Reachability.m
//  GPHTTPRequest
//
//  Created by Dalton Cherry on 6/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

#import <CoreFoundation/CoreFoundation.h>

#import "GPReachability.h"

@interface GPReachability()

-(NetworkStatus)localWiFiStatusForFlags:(SCNetworkReachabilityFlags)flags;
-(NetworkStatus)networkStatusForFlags:(SCNetworkReachabilityFlags)flags;
+(GPReachability*)reachabilityWithAddress:(const struct sockaddr_in*)hostAddress;

@end

@implementation GPReachability

static GPReachability* sharedNotifer;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info)
{
    #pragma unused (target, flags)
	NSCAssert(info != NULL, @"info was NULL in ReachabilityCallback");
	NSCAssert([(NSObject*) info isKindOfClass: [GPReachability class]], @"info was wrong class in ReachabilityCallback");
    
	// in case someone uses the Reachablity object in a different thread.
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	GPReachability* noteObject = (GPReachability*) info;
	// Post a notification to notify the client that the network reachability changed.
	[[NSNotificationCenter defaultCenter] postNotificationName: kReachabilityChangedNotification object: noteObject];
	
	[pool release];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)startNotiferOnBackgroundThread
{
    if(!notiferThread)
    {
        notiferThread = [[NSThread alloc] initWithTarget:self selector:@selector(startNotifier) object:nil];
        [notiferThread start];
    }
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//returns true if success in starting notifier
-(BOOL)startNotifier
{
    if([NSThread isMainThread])
        NSLog(@"we are the main thread");
    else
         NSLog(@"we are on a background thread");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachChanged:) name:kReachabilityChangedNotification object:nil];
	SCNetworkReachabilityContext context = {0, self, NULL, NULL, NULL};
	if(SCNetworkReachabilitySetCallback(reachabilityRef, ReachabilityCallback, &context))
		if(SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode))
			return YES;
	return NO;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)stopNotifier
{
    [notiferThread release];
    notiferThread = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if(reachabilityRef!= NULL)
		SCNetworkReachabilityUnscheduleFromRunLoop(reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//multi cast delegate
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)addListener:(id<GPReachabilityDelegate>)object
{
    if(!delegates)
        delegates = [[NSMutableArray alloc] init];
    [delegates addObject:object];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)removeLister:(id)object
{
    [delegates removeObject:object];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)reachChanged:(NSNotification* )note
{
	GPReachability* curReach = [note object];
	NSParameterAssert([curReach isKindOfClass: [GPReachability class]]);
    for(id<GPReachabilityDelegate>object in delegates)
        if([object respondsToSelector:@selector(reachabilityChanged:)])
            [object reachabilityChanged:curReach];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//ReachabilityStatus
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(NetworkStatus)currentReachabilityStatus
{
    NSAssert(reachabilityRef != NULL, @"currentNetworkStatus called with NULL reachabilityRef");
	NetworkStatus status = NotReachable;
	SCNetworkReachabilityFlags flags;
	if (SCNetworkReachabilityGetFlags(reachabilityRef, &flags))
	{
		if(localWiFiRef)
			status = [self localWiFiStatusForFlags: flags];
		else
			status = [self networkStatusForFlags: flags];
	}
	return status;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(NetworkStatus)localWiFiStatusForFlags:(SCNetworkReachabilityFlags)flags
{
	BOOL status = NotReachable;
	if((flags & kSCNetworkReachabilityFlagsReachable) && (flags & kSCNetworkReachabilityFlagsIsDirect))
		status = ReachableViaWiFi;	
	return status;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (NetworkStatus)networkStatusForFlags:(SCNetworkReachabilityFlags)flags
{
	if ((flags & kSCNetworkReachabilityFlagsReachable) == 0)
		return NotReachable;
    
	BOOL status = NotReachable;
	
	if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0)
		status = ReachableViaWiFi;
	
	
	if ((((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) ||
         (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0))
	{
        if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0)
            status = ReachableViaWiFi;
    }
	
#if	TARGET_OS_IPHONE
	if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN)
		status = ReachableViaWWAN;
#endif
    
	return status;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
-(void)dealloc
{
    [self stopNotifier];
	if(reachabilityRef!= NULL)
		CFRelease(reachabilityRef);

    [delegates release];
    [super dealloc];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//factory methods
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(GPReachability*)reachableWithHost:(NSString*)host
{
    GPReachability* reach = NULL;
	SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, [host UTF8String]);
	if(reachability!= NULL)
	{
		reach= [[[self alloc] init] autorelease];
		if(reach!= NULL)
		{
			reach->reachabilityRef = reachability;
			reach->localWiFiRef = NO;
		}
	}
	return reach;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(GPReachability*)reachableWithWan
{
    struct sockaddr_in zeroAddress;
	bzero(&zeroAddress, sizeof(zeroAddress));
	zeroAddress.sin_len = sizeof(zeroAddress);
	zeroAddress.sin_family = AF_INET;
	return [self reachabilityWithAddress: &zeroAddress];
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(GPReachability*)reachableWithLan
{
    struct sockaddr_in localWifiAddress;
	bzero(&localWifiAddress, sizeof(localWifiAddress));
	localWifiAddress.sin_len = sizeof(localWifiAddress);
	localWifiAddress.sin_family = AF_INET;
	// IN_LINKLOCALNETNUM is defined in <netinet/in.h> as 169.254.0.0
	localWifiAddress.sin_addr.s_addr = htonl(IN_LINKLOCALNETNUM);
	GPReachability* reach = [self reachabilityWithAddress: &localWifiAddress];
	if(reach != NULL)
		reach->localWiFiRef = YES;
    
	return reach;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(GPReachability*)sharedNotifer
{
    if(!sharedNotifer)
    {
        sharedNotifer = [[GPReachability reachableWithWan] retain];
        [sharedNotifer startNotiferOnBackgroundThread];
    }
    return sharedNotifer;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(GPReachability*)reachabilityWithAddress:(const struct sockaddr_in*)hostAddress
{
	SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr*)hostAddress);
	GPReachability* retVal = NULL;
	if(reachability!= NULL)
	{
		retVal= [[[self alloc] init] autorelease];
		if(retVal!= NULL)
		{
			retVal->reachabilityRef = reachability;
			retVal->localWiFiRef = NO;
		}
	}
	return retVal;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
//simplest way to quickly check if a host is up
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(BOOL)isLanReachable
{
    GPReachability* reach = [GPReachability reachableWithLan];
    if([reach currentReachabilityStatus] != NotReachable)
        return YES;
    return NO;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(BOOL)isWanReachable
{
    GPReachability* reach = [GPReachability reachableWithWan];
    if([reach currentReachabilityStatus] == ReachableViaWWAN)
        return YES;
    return NO;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
+(BOOL)isHostReachable:(NSString*)host
{
    GPReachability* reach = [GPReachability reachableWithHost:host];
    if([reach currentReachabilityStatus] != NotReachable)
        return YES;
    return NO;
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
@end
