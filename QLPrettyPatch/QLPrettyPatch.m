#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>
#import <QuickLook/QuickLook.h>
#import <Ruby/ruby.h>
#import <WebKit/WebKit.h>

#define QLMaxFSRepLength (1026)

NSData * GeneratePrettyHTMLForPatchAtURL(CFURLRef patchURLRef, CFBundleRef generatorBundleRef) {
    RUBY_INIT_STACK
    ruby_init();

    ruby_init_loadpath();

    CFURLRef generatorBundleURLRef = CFBundleCopyBundleURL(generatorBundleRef);
    NSBundle *generatorBundle = [NSBundle bundleWithURL:(NSURL *)generatorBundleURLRef];
    CFRelease(generatorBundleURLRef);

    NSString *bundleResourcePath = [generatorBundle resourcePath];

    char bundleResourcePathFSRep[QLMaxFSRepLength];
    [bundleResourcePath getFileSystemRepresentation:bundleResourcePathFSRep maxLength:QLMaxFSRepLength];
    ruby_incpush(bundleResourcePathFSRep);

    NSString *prettyPatchPath = [generatorBundle pathForResource:@"PrettyPatch" ofType:@"rb"];

    char prettyPatchPathFSRep[QLMaxFSRepLength];
    [prettyPatchPath getFileSystemRepresentation:prettyPatchPathFSRep maxLength:QLMaxFSRepLength];
    rb_load_file(prettyPatchPathFSRep);

    ruby_exec(); // or perhaps ruby_run()?

    NSString *patchString = [NSString stringWithContentsOfURL:(NSURL *)patchURLRef encoding:NSUTF8StringEncoding error:NULL];
    const char * patchCString = [patchString cStringUsingEncoding:NSUTF8StringEncoding];

    VALUE rb_PrettyPatchModule = rb_const_get(rb_cObject, rb_intern("PrettyPatch"));
    VALUE rb_patchString = rb_str_new2(patchCString);
    VALUE rb_patchPrettyString = rb_funcall(rb_PrettyPatchModule, rb_intern("prettify"), 1, rb_patchString);

    char * patchPrettyCString = StringValueCStr(rb_patchPrettyString);
    NSString *patchPrettyString = [NSString stringWithCString:patchPrettyCString encoding:NSUTF8StringEncoding];

    ruby_finalize();

    return [patchPrettyString dataUsingEncoding:NSUTF8StringEncoding];
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
