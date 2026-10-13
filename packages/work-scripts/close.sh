adb wait-for-device
adb root
adb shell am broadcast -a SET_OPERATION_UX_RESTRICTION_OFF
adb shell am broadcast -a SET_DISPLAY_UX_RESTRICTION_OFF
