import 'package:everything/data/sync/sync_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The push debounce decides how quickly an edit leaves the device, and how
/// much traffic a burst of edits costs. Both are easy to get subtly wrong, and
/// neither is visible without two devices to compare.
void main() {
  group('push debounce timings', () {
    test('waits long enough to coalesce a burst of edits', () {
      // Ticking off several habits in a row should be one upload, not one per
      // tap, so the delay has to outlast the gap between deliberate taps.
      expect(SyncCoordinator.pushDelay.inMilliseconds, greaterThanOrEqualTo(1000));
    });

    test('uploads soon enough that putting the device down is enough', () {
      expect(SyncCoordinator.pushDelay, lessThanOrEqualTo(const Duration(seconds: 5)));
    });

    test('continuous editing cannot defer an upload forever', () {
      // Each edit restarts the debounce, so without a ceiling a long editing
      // session would never push. The cap has to be longer than the debounce
      // or it would fire first and the debounce would be dead code.
      expect(SyncCoordinator.maxPushDelay, greaterThan(SyncCoordinator.pushDelay));
      expect(SyncCoordinator.maxPushDelay, lessThanOrEqualTo(const Duration(minutes: 1)));
    });

    test('the backstop poll stays frequent enough to feel live', () {
      // This is the only path by which another device's changes arrive, so it
      // bounds how stale the app can be.
      expect(SyncCoordinator.pollInterval, lessThanOrEqualTo(const Duration(minutes: 2)));
      // ...but not so frequent that a phone is polling constantly.
      expect(SyncCoordinator.pollInterval, greaterThanOrEqualTo(const Duration(seconds: 30)));
    });
  });
}
