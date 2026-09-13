// mediaremote-probe.m — tests whether Now Playing data is reachable.
// Build: clang -fobjc-arc -framework Foundation -o mediaremote-probe mediaremote-probe.m
// IMPORTANT: run this with audio ACTUALLY PLAYING. An empty dict while paused
// proves nothing. Non-empty => MediaRemote works; empty while playing => gated,
// use the AppleScript fallback. This is the project's one open question.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
typedef void (*MRGetNowPlayingInfoFn)(dispatch_queue_t, void(^)(NSDictionary*));
typedef void (*MRGetNowPlayingAppFn)(dispatch_queue_t, void(^)(id));
int main() { @autoreleasepool {
  void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
  printf("MediaRemote dlopen: %s\n", h ? "OK" : dlerror());
  if (!h) return 1;
  const char *syms[] = {"MRMediaRemoteGetNowPlayingInfo","MRMediaRemoteSendCommand",
                        "MRMediaRemoteGetNowPlayingApplicationIsPlaying","MRNowPlayingClientGetBundleIdentifier"};
  for (int i=0;i<4;i++) printf("  %-50s %s\n", syms[i], dlsym(h,syms[i]) ? "FOUND" : "MISSING");
  MRGetNowPlayingInfoFn fn = (MRGetNowPlayingInfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
  if (!fn) return 1;
  __block BOOL done = NO;
  fn(dispatch_get_main_queue(), ^(NSDictionary *info) {
    if (!info || info.count == 0) printf("\n>>> RESULT: empty/nil dict — LIKELY ENTITLEMENT-BLOCKED\n");
    else { printf("\n>>> RESULT: got %lu keys — WORKS\n", (unsigned long)info.count);
      for (NSString *k in info) printf("    %s\n", [k UTF8String]); }
    done = YES;
  });
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:4.0]];
  if (!done) printf("\n>>> RESULT: callback NEVER FIRED — blocked\n");
  return 0;
}}
