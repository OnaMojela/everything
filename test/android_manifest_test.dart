import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards a failure mode that only ever appears in a release build.
///
/// Flutter injects `android.permission.INTERNET` into debug and profile
/// manifests so the tooling can attach a debugger, so `flutter run` works
/// whether or not the main manifest declares it. A release APK gets only what
/// the main manifest asks for — and without INTERNET, Supabase fails to
/// initialise on launch and the app crash-loops before it can render.
void main() {
  test('release manifest declares the INTERNET permission', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      manifest,
      contains('android.permission.INTERNET'),
      reason: 'Without it, release builds cannot reach Supabase and sync is '
          'dead on Android — debug builds will not reveal this.',
    );
  });
}
