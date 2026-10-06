# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# Play Core (required by Flutter engine)
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-dontwarn com.google.android.play.core.**

# Keep entry points
-keep class * extends io.flutter.embedding.android.FlutterActivity { *; }
-keep class * extends io.flutter.embedding.android.FlutterFragment { *; }
-keep class * extends io.flutter.embedding.android.FlutterApplication { *; }

# audioplayers
-keep class xyz.luan.audioplayers.** { *; }
-dontwarn xyz.luan.audioplayers.**

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Google Play Billing (in_app_purchase) — support-the-developer coffee tiers
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**
-keep class io.flutter.plugins.inapppurchase.** { *; }

# OkHttp / networking
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# Google Fonts
-keep class com.google.fonts.** { *; }

# General
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
