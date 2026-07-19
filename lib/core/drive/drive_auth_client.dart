import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../auth/desktop_google_auth.dart';
import '../auth/google_auth_service.dart';

/// An HTTP client that injects the Google access token into every request.
/// Used to authenticate Google Drive API calls.
class DriveAuthClient extends http.BaseClient {
  final http.Client _inner;

  DriveAuthClient({http.Client? inner}) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _getAccessToken();
    if (token == null) {
      throw const GoogleSignInSetupException(
          'Not signed in with Google — sign in from Settings before syncing.');
    }
    request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request);
  }

  Future<String?> _getAccessToken() async {
    if (useDesktopGoogleAuth) {
      return DesktopGoogleAuth.instance.getAccessToken();
    }

    await ensureGoogleSignInInitialized();
    final account =
        await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) return null;

    final authorization =
        await account.authorizationClient.authorizationForScopes([
      'https://www.googleapis.com/auth/drive.file',
    ]);
    return authorization?.accessToken;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
