import 'package:flutter/services.dart';

/// Every vibration in the app goes through here, so each event has exactly one
/// feel. Android mappings (Flutter 3.44 `HapticFeedback`): long press is
/// LONG_PRESS, tick is CLOCK_TICK, light is VIRTUAL_KEY, success is CONFIRM and
/// error is REJECT (the last two need API 30, our minSdk).
abstract final class AppHaptics {
  /// A long-press that starts selecting.
  static Future<void> longPress() => HapticFeedback.vibrate();

  /// A discrete step: an item added by drag-select, a grid zoom level, a month
  /// passed on the scrubber, a swipe crossing its threshold.
  static Future<void> tick() => HapticFeedback.selectionClick();

  /// A small confirmed toggle: favourite on, a video skip, hold for 2x.
  static Future<void> light() => HapticFeedback.lightImpact();

  /// A long task finished: extract, import, move.
  static Future<void> success() => HapticFeedback.successNotification();

  /// An action was refused: invalid input, a failed task.
  static Future<void> error() => HapticFeedback.errorNotification();
}
