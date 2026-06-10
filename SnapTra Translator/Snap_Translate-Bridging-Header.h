//
//  Snap_Translate-Bridging-Header.h
//  Snap Translate
//

#ifndef Snap_Translate_Bridging_Header_h
#define Snap_Translate_Bridging_Header_h

#import <CommonCrypto/CommonCrypto.h>
#import <CoreServices/CoreServices.h>

// Private Dictionary Services APIs (exported symbols, not in public header).
// We use DCSDictionaryRef (from the public DictionaryServices header) so that
// values returned here can be passed directly to DCSCopyTextDefinition().
extern CFArrayRef __nullable DCSCopyAvailableDictionaries(void);
extern CFStringRef __nullable DCSDictionaryGetName(DCSDictionaryRef dictionary);

#endif
