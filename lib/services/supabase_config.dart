import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const defaultUrl = 'https://anszxslagplhqofakabk.supabase.co';
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: defaultUrl,
  );
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  static SupabaseClient? tryClient() {
    if (!isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
