import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const defaultUrl = 'https://anszxslagplhqofakabk.supabase.co';
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: defaultUrl,
  );
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
  static bool _initialized = false;

  static bool get isInitialized => _initialized;
  static bool get isAvailable => isConfigured && isInitialized;

  static Future<void> initialize() async {
    _initialized = false;
    if (!isConfigured) return;
    try {
      await Supabase.initialize(url: url, anonKey: anonKey);
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  static SupabaseClient? tryClient() {
    if (!isAvailable) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
