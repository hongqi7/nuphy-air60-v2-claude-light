// kbled: list keyboards and set their LED elements (Num/Caps/Scroll) via IOKit.
// usage: kbled list
//        kbled set  <name-substring> <num|caps|scroll> <0|1>
//        kbled bits <name-substring> <num 0|1> <scroll 0|1>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDUsageTables.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static void cfstr(CFTypeRef v, char *buf, size_t n) {
    buf[0] = 0;
    if (v && CFGetTypeID(v) == CFStringGetTypeID())
        CFStringGetCString((CFStringRef)v, buf, n, kCFStringEncodingUTF8);
}

static long cfnum(CFTypeRef v) {
    long x = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)v, kCFNumberLongType, &x);
    return x;
}

static void usage(void) {
    fprintf(stderr, "usage: kbled list | set <name> <num|caps|scroll> <0|1> | bits <name> <num 0|1> <scroll 0|1>\n"
                    "       kbled watch <name> <command>   run command when the keyboard connects and every 20s\n");
}

// watch mode: a reconnected keyboard starts with its LEDs cleared, so re-apply the state
static const char *watchName, *watchCmd;

static void runWatchCmd(CFRunLoopTimerRef t, void *info) {
    (void)t; (void)info;
    if (system(watchCmd) != 0) fprintf(stderr, "command failed: %s\n", watchCmd);
}

static void deviceMatched(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef dev) {
    (void)ctx; (void)res; (void)sender;
    char name[256];
    cfstr(IOHIDDeviceGetProperty(dev, CFSTR(kIOHIDProductKey)), name, sizeof name);
    if (!strcasestr(name, watchName)) return;
    // give the link a moment to settle before writing LEDs
    CFRunLoopTimerRef once = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 2, 0, 0, 0, runWatchCmd, NULL);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), once, kCFRunLoopDefaultMode);
    CFRelease(once);
}

static int watch(IOHIDManagerRef mgr) {
    IOHIDManagerRegisterDeviceMatchingCallback(mgr, deviceMatched, NULL);
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    CFRunLoopTimerRef tick = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 20, 20, 0, 0, runWatchCmd, NULL);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), tick, kCFRunLoopDefaultMode);
    CFRunLoopRun();
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 2; }
    if (!strcmp(argv[1], "watch")) {
        if (argc < 4) { usage(); return 2; }
        watchName = argv[2];
        watchCmd  = argv[3];
    }
    int doList = !strcmp(argv[1], "list");
    int doSet  = !strcmp(argv[1], "set");
    int doBits = !strcmp(argv[1], "bits");
    if (!doList && !doSet && !doBits && !watchCmd) { usage(); return 2; }
    if ((doSet || doBits) && argc < 5) { usage(); return 2; }

    // wanted[usage] = value, or -1 to leave alone
    int wanted[6] = { -1, -1, -1, -1, -1, -1 };
    if (doSet) {
        uint32_t u;
        if (!strcmp(argv[3], "num")) u = kHIDUsage_LED_NumLock;
        else if (!strcmp(argv[3], "caps")) u = kHIDUsage_LED_CapsLock;
        else if (!strcmp(argv[3], "scroll")) u = kHIDUsage_LED_ScrollLock;
        else { fprintf(stderr, "unknown led %s\n", argv[3]); return 2; }
        wanted[u] = atoi(argv[4]);
    } else if (doBits) {
        wanted[kHIDUsage_LED_NumLock]    = atoi(argv[3]);
        wanted[kHIDUsage_LED_ScrollLock] = atoi(argv[4]);
    }

    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    int page = kHIDPage_GenericDesktop, usg = kHIDUsage_GD_Keyboard;
    CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef u = CFNumberCreate(NULL, kCFNumberIntType, &usg);
    const void *keys[] = { CFSTR(kIOHIDDeviceUsagePageKey), CFSTR(kIOHIDDeviceUsageKey) };
    const void *vals[] = { p, u };
    CFDictionaryRef match = CFDictionaryCreate(NULL, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(mgr, match);
    IOReturn r = IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
    if (r != kIOReturnSuccess) fprintf(stderr, "IOHIDManagerOpen: 0x%x (Input Monitoring permission?)\n", r);
    if (watchCmd) return watch(mgr);

    CFSetRef set = IOHIDManagerCopyDevices(mgr);
    if (!set) { fprintf(stderr, "no keyboards found\n"); return 1; }
    CFIndex n = CFSetGetCount(set);
    IOHIDDeviceRef *devs = malloc(sizeof(IOHIDDeviceRef) * n);
    CFSetGetValues(set, (const void **)devs);

    int hits = 0;
    for (CFIndex i = 0; i < n; i++) {
        char name[256], transport[64];
        cfstr(IOHIDDeviceGetProperty(devs[i], CFSTR(kIOHIDProductKey)), name, sizeof name);
        cfstr(IOHIDDeviceGetProperty(devs[i], CFSTR(kIOHIDTransportKey)), transport, sizeof transport);
        long vid = cfnum(IOHIDDeviceGetProperty(devs[i], CFSTR(kIOHIDVendorIDKey)));
        long pid = cfnum(IOHIDDeviceGetProperty(devs[i], CFSTR(kIOHIDProductIDKey)));

        if (doList) printf("[%ld] \"%s\" transport=%s vid=0x%04lx pid=0x%04lx\n", i, name, transport, vid, pid);
        else if (!strcasestr(name, argv[2])) continue;

        CFArrayRef els = IOHIDDeviceCopyMatchingElements(devs[i], NULL, kIOHIDOptionsTypeNone);
        if (!els) continue;
        for (CFIndex j = 0; j < CFArrayGetCount(els); j++) {
            IOHIDElementRef e = (IOHIDElementRef)CFArrayGetValueAtIndex(els, j);
            if (IOHIDElementGetUsagePage(e) != kHIDPage_LEDs) continue;
            uint32_t eu = IOHIDElementGetUsage(e);
            if (doList) { printf("     LED usage 0x%02x\n", eu); continue; }
            if (eu >= 6 || wanted[eu] < 0) continue;
            IOHIDValueRef v = IOHIDValueCreateWithIntegerValue(NULL, e, 0, wanted[eu]);
            IOReturn sr = IOHIDDeviceSetValue(devs[i], e, v);
            if (sr != kIOReturnSuccess) fprintf(stderr, "set \"%s\" led 0x%02x -> 0x%x\n", name, eu, sr);
            CFRelease(v);
            hits++;
        }
        CFRelease(els);
    }
    if (!doList && !hits) { fprintf(stderr, "no matching device/LED\n"); return 1; }
    return 0;
}
