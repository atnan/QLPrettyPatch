#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>
#import <QuickLook/QuickLook.h>
#import <WebKit/WebKit.h>

NSData * GeneratePrettyHTMLForPatchAtURL(CFURLRef patchURLRef, CFBundleRef generatorBundleRef) {
    NSTask *task = [[[NSTask alloc] init] autorelease];
    task.launchPath = [@"/usr/bin/ruby" stringByStandardizingPath];

    CFURLRef generatorBundleURLRef = CFBundleCopyBundleURL(generatorBundleRef);
    NSBundle *generatorBundle = [NSBundle bundleWithURL:(NSURL *)generatorBundleURLRef];
    CFRelease(generatorBundleURLRef);
    
    NSString *bundleResourcePath = [generatorBundle resourcePath];
    
    NSString *prettyPatchLibraryPath = [NSString stringWithFormat:@"-I\"%@\"", bundleResourcePath];
    NSString *prettyPatchPath = [generatorBundle pathForResource:@"PrettyPatch" ofType:@"rb"];
    NSString *patchPath = [(NSURL *)patchURLRef path];

    task.arguments = @[ prettyPatchLibraryPath, prettyPatchPath, patchPath ];

    NSLog(@"task.launchPath = %@", task.launchPath);
    NSLog(@"task.arguments = %@", task.arguments);

    char cpath[1026];
    [task.launchPath getFileSystemRepresentation:cpath maxLength:1026];
    int pathIsExecutable = access("/usr/bin/ruby", X_OK);

    uid_t uid = getuid();
    uid_t euid = geteuid();
    NSLog(@"uid = %d, euid = %d, pathIsExecutable = %d, errno = %d", uid, euid, pathIsExecutable, errno);

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;

    @try {
        [task launch];
        
    } @catch (NSException *exception) {
        NSLog(@"Failed to launch task with exception: %@", exception);
        return nil;
    }

    [task waitUntilExit];

    return [[pipe fileHandleForReading] readDataToEndOfFile];
}

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options) {
    NSData *prettyPatchData = GeneratePrettyHTMLForPatchAtURL(url, QLPreviewRequestGetGeneratorBundle(preview));
    if (prettyPatchData) {
        QLPreviewRequestSetDataRepresentation(preview, (CFDataRef)prettyPatchData, kUTTypeHTML, (CFDictionaryRef)@{});
    }
    return noErr;
}

OSStatus GenerateThumbnailForURL(void *thisInterface, QLThumbnailRequestRef thumbnail, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options, CGSize maxSize) {
    NSData *prettyPatchData = GeneratePrettyHTMLForPatchAtURL(url, QLThumbnailRequestGetGeneratorBundle(thumbnail));
    if (!prettyPatchData) return noErr;
    
    NSRect viewRect = NSMakeRect(0.f, 0.f, 600.f, 800.f);
    float scale = maxSize.height / 800.0;
    NSSize scaleSize = NSMakeSize(scale, scale);
    CGSize thumbSize = NSSizeToCGSize(NSMakeSize((maxSize.width * (600.0/800.0)), maxSize.height));

    WebView* webView = [[[WebView alloc] initWithFrame:viewRect] autorelease];
    [webView scaleUnitSquareToSize:scaleSize];
    [[[webView mainFrame] frameView] setAllowsScrolling:NO];
    [[webView mainFrame] loadData:prettyPatchData
                         MIMEType:@"text/html"
                 textEncodingName:@"utf-8"
                          baseURL:nil];

    while ([webView isLoading]) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
    }

    [webView display];

    CGContextRef context = QLThumbnailRequestCreateContext(thumbnail, thumbSize, false, NULL);

    if (context) {
        NSGraphicsContext* nsContext = [NSGraphicsContext graphicsContextWithGraphicsPort:(void *)context
                                                                                  flipped:[webView isFlipped]];

        [webView displayRectIgnoringOpacity:[webView bounds]
                                  inContext:nsContext];

        QLThumbnailRequestFlushContext(thumbnail, context);
        CFRelease(context);
    }

    return noErr;
}

void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview) { /* not supported */ }
void CancelThumbnailGeneration(void *thisInterface, QLThumbnailRequestRef thumbnail) { /* not supported */ }
