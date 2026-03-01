
import 'dart:async';

class AndroidAlarmManager {
  static Future<bool> initialize() async {
    // On non-Android platforms, this is a no-op.
    return true;
  }

  static Future<bool> oneShotAt(
    DateTime time,
    int id,
    void Function() callback, {
    bool exact = false,
    bool wakeup = false,
    bool allowWhileIdle = false,
    bool rescheduleOnReboot = false,
  }) async {
    // On non-Android platforms, this is a no-op.
    return true;
  }

  static Future<bool> cancel(int id) async {
    // On non-Android platforms, this is a no-op.
    return true;
  }
}
