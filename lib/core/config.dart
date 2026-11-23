/// Build-time configuration.
///
/// Values are passed with --dart-define when building, e.g.
///   flutter build apk --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///                     --dart-define=SUPABASE_ANON_KEY=eyJ...
/// The GitHub workflow passes them from repository secrets automatically.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Optional link shown in Profile → Privacy policy (required by Google Play).
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');

  /// Deep link used for Google sign-in, email confirmation and password reset.
  /// Must also be added in Supabase → Authentication → URL Configuration.
  static const authRedirect = 'com.bodiana.app://login-callback';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
