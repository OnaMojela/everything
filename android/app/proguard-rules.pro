# R8 rules for release builds.
#
# Flutter enables R8 for release, which shrinks and renames Java/Kotlin code.
# Anything looked up reflectively therefore has to be kept explicitly — the
# failures only ever appear in a release build, as a crash at process start
# with no Dart stack trace to point at the cause.

# ---------------------------------------------------------------------------
# Room / WorkManager
# ---------------------------------------------------------------------------
# WorkManager (pulled in by home_widget) stores its queue in a Room database.
# Room resolves the generated implementation by name and instantiates it
# reflectively: `Class.forName("androidx.work.impl.WorkDatabase_Impl")` then
# `newInstance()`. R8 kept the class but removed its no-arg constructor, since
# nothing calls it directly — which surfaced as:
#
#   java.lang.RuntimeException: Unable to get provider
#     androidx.startup.InitializationProvider: Failed to create an instance of
#     androidx.work.impl.WorkDatabase
#
# That is thrown before Flutter starts, so the app crash-looped on launch.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.room.RoomDatabase { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase { <init>(); }
-dontwarn androidx.room.paging.**

-keep class androidx.work.impl.WorkDatabase_Impl { <init>(); }
-keep class * extends androidx.work.Worker { <init>(...); }
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-keep class androidx.work.impl.background.systemalarm.RescheduleReceiver
-keep class androidx.work.impl.background.systemjob.SystemJobService { <init>(); }

# androidx.startup discovers initialisers from the manifest by class name.
-keep class * extends androidx.startup.Initializer { <init>(); }
-keep class androidx.startup.InitializationProvider { <init>(); }

# ---------------------------------------------------------------------------
# Plugins that resolve classes by name
# ---------------------------------------------------------------------------
# Scheduled habit and bill reminders survive reboots via a broadcast receiver
# named in the manifest, so it must keep its name.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# Home-screen widget providers are named in the manifest and in XML.
-keep class * extends android.appwidget.AppWidgetProvider { *; }
-keep class com.everything.everything.** { *; }

# The bank-notification listener is bound by the system by class name.
-keep class * extends android.service.notification.NotificationListenerService { *; }

# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
# Keep the annotations R8 itself relies on to make keep decisions.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
