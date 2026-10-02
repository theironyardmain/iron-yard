# Drift / sqlite3 load native code reflectively; R8 must not strip it.
-keep class io.flutter.plugins.** { *; }
-keep class com.google.crypto.tink.** { *; }

# flutter_local_notifications keeps scheduled notifications across a reboot
# via a receiver R8 cannot see referenced.
-keep class com.dexterous.** { *; }

# mobile_scanner (ML Kit barcode).
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
