//
//  QLPrettyPatch.m
//  QLPrettyPatch
//
//  Created by Nathan de Vries on 1/1/2013.
//  Copyright 2013 Nathan de Vries. All rights reserved.
//

#import <QuickLook/QuickLook.h>
#import <Ruby/ruby.h>
#import <WebKit/WebKit.h>

#ifdef DEBUG
#   define QLDebugLog(...) NSLog(__VA_ARGS__)
#else
#   define QLDebugLog(...)
#endif

#define QLMaxPathSize 1026
#define QLMaxPathLength 1024

NSData *GeneratePrettyHTMLForPatchAtURL(CFURLRef patchURLRef, CFBundleRef generatorBundleRef) {
    RUBY_INIT_STACK
    ruby_init();
    ruby_init_loadpath();

    CFURLRef generatorBundleURLRef = CFBundleCopyBundleURL(generatorBundleRef);
    NSBundle *generatorBundle = [NSBundle bundleWithURL:(NSURL *)generatorBundleURLRef];
    CFRelease(generatorBundleURLRef);

    NSString *bundleResourcePath = [generatorBundle resourcePath];

    char bundleResourcePathFSRep[QLMaxPathSize];
    [bundleResourcePath getFileSystemRepresentation:bundleResourcePathFSRep maxLength:QLMaxPathLength];
    ruby_incpush(bundleResourcePathFSRep);

    NSString *prettyPatchPath = [generatorBundle pathForResource:@"PrettyPatch" ofType:@"rb"];

    char prettyPatchPathFSRep[QLMaxPathSize];
    [prettyPatchPath getFileSystemRepresentation:prettyPatchPathFSRep maxLength:QLMaxPathLength];
    rb_load_file(prettyPatchPathFSRep);

    int rb_execStatus = ruby_exec();
    QLDebugLog(@"ruby_exec() returned status code %d.", rb_execStatus);

    void (^cleanup_and_finalize_ruby)(void) = ^{
        ruby_cleanup(rb_execStatus);
        ruby_finalize();
    };

    NSError *error = nil;
    NSString *patchString = [NSString stringWithContentsOfURL:(NSURL *)patchURLRef encoding:NSUTF8StringEncoding error:&error];
    if (!patchString) {
        QLDebugLog(@"Failed to read patch file at URL '%@' (%@).", (NSURL *)patchURLRef, [error localizedDescription]);
        cleanup_and_finalize_ruby();
        return nil;
    }

    const char * patchCString = [patchString cStringUsingEncoding:NSUTF8StringEncoding];

    VALUE rb_PrettyPatchModule = rb_const_get(rb_cObject, rb_intern("PrettyPatch"));
    VALUE rb_patchString = rb_str_new2(patchCString);
    VALUE rb_patchPrettyString = rb_funcall(rb_PrettyPatchModule, rb_intern("prettify"), 1, rb_patchString);

    char * patchPrettyCString = StringValueCStr(rb_patchPrettyString);
    NSString *patchPrettyString = [NSString stringWithCString:patchPrettyCString encoding:NSUTF8StringEncoding];

    cleanup_and_finalize_ruby();

    return [patchPrettyString dataUsingEncoding:NSUTF8StringEncoding];
}

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options) {
    NSData *prettyPatchData = GeneratePrettyHTMLForPatchAtURL(url, QLPreviewRequestGetGeneratorBundle(preview));
    if (prettyPatchData) {
        QLPreviewRequestSetDataRepresentation(preview, (CFDataRef)prettyPatchData, kUTTypeHTML, (CFDictionaryRef)@{});
        return kQLReturnNoError;
    } else {
        return -1;
    }
}

OSStatus GenerateThumbnailForURL(void *thisInterface, QLThumbnailRequestRef thumbnail, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options, CGSize maxSize) {
    NSData *prettyPatchData = GeneratePrettyHTMLForPatchAtURL(url, QLThumbnailRequestGetGeneratorBundle(thumbnail));
    if (!prettyPatchData) return noErr;
    
    NSRect viewRect = NSMakeRect(0, 0, 600, 800);
    CGFloat scale = maxSize.height / 800;
    NSSize scaleSize = NSMakeSize(scale, scale);
    CGSize thumbSize = NSSizeToCGSize(NSMakeSize((maxSize.width * (600 / 800)), maxSize.height));

    WebView* webView = [[[WebView alloc] initWithFrame:viewRect] autorelease];
    [webView scaleUnitSquareToSize:scaleSize];
    webView.mainFrame.frameView.allowsScrolling = NO;
    [[webView mainFrame] loadData:prettyPatchData MIMEType:@"text/html" textEncodingName:@"utf-8" baseURL:nil];

    while ([webView isLoading]) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
    }

    [webView display];

    CGContextRef context = QLThumbnailRequestCreateContext(thumbnail, thumbSize, false, NULL);

    if (context) {
        NSGraphicsContext* nsContext = [NSGraphicsContext graphicsContextWithGraphicsPort:(void *)context flipped:[webView isFlipped]];

        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:nsContext];

        [webView displayRectIgnoringOpacity:[webView bounds] inContext:nsContext];

        QLThumbnailRequestFlushContext(thumbnail, context);
        CFRelease(context);

        [NSGraphicsContext restoreGraphicsState];

        return kQLReturnNoError;

    } else {
        return -1;
    }
}

void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview) { /* not supported */ }
void CancelThumbnailGeneration(void *thisInterface, QLThumbnailRequestRef thumbnail) { /* not supported */ }
