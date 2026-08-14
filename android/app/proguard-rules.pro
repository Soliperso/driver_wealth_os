# R8 is enabled for release builds. Flutter's own rules come from the Gradle
# plugin; these cover the plugins this app uses that rely on reflection.

# Geolocator's foreground service and its settings objects are resolved by name
# from the platform channel, so shrinking them breaks mileage tracking in
# release builds only — the worst kind of bug to find late.
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }

# Argyle Link's native SDK is driven entirely over a method channel.
-keep class com.argyle.** { *; }
