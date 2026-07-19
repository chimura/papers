/// OAuth 2.0 "Desktop app" client credentials used for Google sign-in on
/// Windows/Linux, where the google_sign_in plugin has no implementation.
///
/// Setup (one time, ~2 minutes):
///  1. Open https://console.cloud.google.com/apis/credentials?project=papers-sci
///  2. Create Credentials → OAuth client ID → Application type: "Desktop app"
///  3. Paste the client ID and client secret below (or pass them at build time
///     with --dart-define=GOOGLE_DESKTOP_CLIENT_ID=... and
///     --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...)
///
/// Note: for installed ("Desktop app") clients Google does not treat the
/// client secret as confidential — it necessarily ships inside the app.
/// Still, avoid committing real values to a public repository.
class DesktopOAuthConfig {
  static const String clientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
    defaultValue: '',
  );

  static const String clientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
    defaultValue: '',
  );

  static bool get isConfigured => clientId.isNotEmpty;
}
