#ifndef DictionaryServiceExtension_h
#define DictionaryServiceExtension_h

#import <CoreServices/CoreServices.h>

CF_EXTERN_C_BEGIN

CFArrayRef _Nullable DCSCopyAvailableDictionaries(void);
CFArrayRef _Nullable DCSGetActiveDictionaries(void);
CFStringRef _Nullable DCSDictionaryGetName(DCSDictionaryRef _Nullable dictionary);
CFStringRef _Nullable DCSDictionaryGetShortName(DCSDictionaryRef _Nullable dictionary);
CFStringRef _Nullable DCSDictionaryGetIdentifier(DCSDictionaryRef _Nullable dictionary);

CF_EXTERN_C_END

#endif
