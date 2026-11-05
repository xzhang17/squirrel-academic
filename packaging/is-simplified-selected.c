/* Read the actual macOS selection because the nightly's CLI returns success
 * even when macOS defers activation until the next desktop login. */
#include <Carbon/Carbon.h>

int main(void) {
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (source == NULL) return 1;
    CFStringRef source_id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    Boolean selected = source_id && CFEqual(source_id, CFSTR("im.rime.inputmethod.Squirrel.Hans"));
    CFRelease(source);
    return selected ? 0 : 1;
}
