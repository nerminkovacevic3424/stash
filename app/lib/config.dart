import 'package:flutter/foundation.dart';

/// Build-time configuration. Pass with `--dart-define=NAME=value`.
class Config {
  static const _backend = String.fromEnvironment('STASH_BACKEND_URL');

  /// Defaults to a backend running on the development machine.
  static String get backendUrl {
    if (_backend.isNotEmpty) return _backend;
    // The web app is served by the backend itself, so it talks to its own origin.
    if (kIsWeb) return Uri.base.origin;
    return defaultTargetPlatform == TargetPlatform.android ? 'http://10.0.2.2:8787' : 'http://127.0.0.1:8787';
  }

  static const appKey = String.fromEnvironment('STASH_APP_KEY');

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get syncConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Must match the App Group on both iOS targets and `appGroupId` in
  /// ios/StashShare/SharedStore.swift.
  static const appGroupId = 'group.com.example.stash';

  /// How long the share sheet waits for a smart suggestion before falling back.
  static const suggestionBudget = Duration(milliseconds: 1500);
}
