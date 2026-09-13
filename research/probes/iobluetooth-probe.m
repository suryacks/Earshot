// iobluetooth-probe.m — enumerates paired devices via PUBLIC IOBluetooth.
// Build: clang -fobjc-arc -framework Foundation -framework IOBluetooth -o iobluetooth-probe iobluetooth-probe.m
// Confirms openConnection/closeConnection exist — no private API needed to connect.

#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
int main() { @autoreleasepool {
  NSArray *paired = [IOBluetoothDevice pairedDevices];
  printf("pairedDevices: %lu\n", (unsigned long)paired.count);
  for (IOBluetoothDevice *d in paired) {
    printf("  %-28s connected=%d  [openConnection=%d closeConnection=%d]\n",
      [(d.name ?: @"?") UTF8String], d.isConnected,
      [d respondsToSelector:@selector(openConnection)],
      [d respondsToSelector:@selector(closeConnection)]);
  }
  return 0;
}}
