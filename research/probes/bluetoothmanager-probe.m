// bluetoothmanager-probe.m — tries the PRIVATE BluetoothManager.framework.
// Build: clang -fobjc-arc -framework Foundation -Wno-objc-method-access -o bluetoothmanager-probe bluetoothmanager-probe.m
// RESULT: available=0, 0 devices, even ad-hoc signed. bluetoothd rejects unsigned clients.
// Kept as evidence of a dead end — see docs/FEASIBILITY.md section 8.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
int main() { @autoreleasepool {
  dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_NOW);
  id mgr = [NSClassFromString(@"BluetoothManager") performSelector:@selector(sharedInstance)];
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3.0]];
  printf("available=%d powered=%d\n",
    [mgr respondsToSelector:@selector(available)] ? (int)[mgr performSelector:@selector(available)] : -1,
    [mgr respondsToSelector:@selector(enabled)] ? (int)[mgr performSelector:@selector(enabled)] : -1);
  NSArray *a = [mgr performSelector:@selector(connectedDevices)];
  printf("connectedDevices: %lu\n", (unsigned long)[a count]);
  for (id d in a) {
    printf("  name=%s\n", [[d performSelector:@selector(name)] UTF8String]);
    for (NSString *s in @[@"batteryPercentCombined",@"batteryPercentLeft",@"batteryPercentRight",@"batteryPercentCase"]) {
      SEL sel = NSSelectorFromString(s);
      if ([d respondsToSelector:sel]) {
        NSMethodSignature *sig = [d methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel]; [inv setTarget:d]; [inv invoke];
        NSInteger v = 0; [inv getReturnValue:&v];
        printf("    %s = %ld\n", [s UTF8String], (long)v);
      } else printf("    %s = <no selector>\n", [s UTF8String]);
    }
  }
  return 0;
}}
