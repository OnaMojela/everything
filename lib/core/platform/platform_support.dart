import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Single source of truth for which platform capabilities exist. The web build
/// hides anything it cannot honestly deliver rather than showing dead controls.
bool get isWeb => kIsWeb;

bool get _isMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Scheduled local notifications (habit reminders, bill alerts, focus alarms).
bool get supportsNotifications => _isMobile;

/// Biometric / device-PIN app lock.
bool get supportsAppLock => _isMobile;

/// Android home-screen widgets.
bool get supportsHomeWidgets => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
