#!/bin/sh
# Chrome reads enterprise policies from the com.google.Chrome preference
# domain; no MDM needed. Written policies show up in chrome://policy as
# mandatory and cannot be changed from the UI or by an extension. Chrome
# picks them up on its next start.
set -eu

D=com.google.Chrome

# Only these extensions may be installed. Chrome's own component
# extensions (Google Wallet and friends) are exempt from the blocklist.
defaults write "$D" ExtensionInstallBlocklist -array '*'
defaults write "$D" ExtensionInstallAllowlist -array \
  fcoeoabgfenejglbffodgkkbkcdhcgfn

# No V8 JIT: most Chrome 0-days are V8 bugs. Add slow sites to the
# allow list as they turn up.
defaults write "$D" DefaultJavaScriptJitSetting -int 2
defaults write "$D" JavaScriptJitAllowedForSites -array

defaults write "$D" HttpsOnlyMode -string force_enabled
defaults write "$D" BlockThirdPartyCookies -bool true
defaults write "$D" SafeBrowsingProtectionLevel -int 1

# Web pages get no access to USB, serial, Bluetooth or HID devices.
defaults write "$D" DefaultWebUsbGuardSetting -int 2
defaults write "$D" DefaultSerialGuardSetting -int 2
defaults write "$D" DefaultWebBluetoothGuardSetting -int 2
defaults write "$D" DefaultWebHidGuardSetting -int 2

# Passwords and cards live in the password manager, not in Chrome.
defaults write "$D" PasswordManagerEnabled -bool false
defaults write "$D" AutofillCreditCardEnabled -bool false

defaults write "$D" RemoteAccessHostAllowRemoteAccessConnections -bool false

echo "Chrome policies written. Restart Chrome and check chrome://policy."
