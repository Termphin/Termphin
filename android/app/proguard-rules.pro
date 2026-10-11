# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep method signatures for reflection-safe serialization
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod

# Flutter references Play Core classes that aren't on classpath — safe to ignore
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
