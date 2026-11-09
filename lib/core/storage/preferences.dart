import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small, non-sensitive settings: video loop and mute, album pins, covers and
/// sort orders. Nothing secret is ever stored here.
final Provider<SharedPreferencesAsync> preferencesProvider =
    Provider<SharedPreferencesAsync>((Ref ref) => SharedPreferencesAsync());
