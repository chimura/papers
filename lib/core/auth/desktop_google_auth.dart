import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'desktop_oauth_config.dart';

/// Thrown when Google sign-in cannot proceed for a reason the user can fix.
class GoogleSignInSetupException implements Exception {
  final String message;
  const GoogleSignInSetupException(this.message);

  @override
  String toString() => message;
}

/// Google sign-in for desktop platforms (Windows/Linux), where the
/// google_sign_in plugin is not available.
///
/// Runs the OAuth 2.0 authorization-code flow with PKCE against a loopback
/// redirect: a local HTTP server is started on an ephemeral port, the system
/// browser opens the Google consent screen, and Google redirects back to the
/// local server with the authorization code. The resulting ID token signs the
/// user into Firebase; the access/refresh tokens authorize Google Drive calls.
class DesktopGoogleAuth {
  DesktopGoogleAuth._();
  static final DesktopGoogleAuth instance = DesktopGoogleAuth._();

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _scopes = [
    'openid',
    'email',
    'profile',
    'https://www.googleapis.com/auth/drive.file',
  ];
  static const _refreshTokenKey = 'desktop_google_refresh_token';

  String? _accessToken;
  DateTime? _accessTokenExpiry;

  Future<UserCredential> signIn() async {
    if (!DesktopOAuthConfig.isConfigured) {
      throw const GoogleSignInSetupException(
        'Google sign-in is not configured for desktop yet.\n'
        'Create a "Desktop app" OAuth client for the papers-sci project in '
        'the Google Cloud console and add its credentials to '
        'lib/core/auth/desktop_oauth_config.dart.',
      );
    }

    final tokens = await _runLoopbackFlow();

    _accessToken = tokens.accessToken;
    _accessTokenExpiry = tokens.expiry;
    if (tokens.refreshToken != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_refreshTokenKey, tokens.refreshToken!);
    }

    final credential = GoogleAuthProvider.credential(
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  /// A valid Drive-scoped access token, refreshed if needed.
  /// Returns null when the user has never completed a desktop sign-in.
  Future<String?> getAccessToken() async {
    final token = _accessToken;
    final expiry = _accessTokenExpiry;
    if (token != null &&
        expiry != null &&
        expiry.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return token;
    }
    return _refreshAccessToken();
  }

  Future<void> signOut() async {
    _accessToken = null;
    _accessTokenExpiry = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_refreshTokenKey);
  }

  Future<_TokenResponse> _runLoopbackFlow() async {
    final verifier = _randomUrlSafeString(64);
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final state = _randomUrlSafeString(32);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';

      final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
        'client_id': DesktopOAuthConfig.clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': _scopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        // Ensure a refresh token is issued so Drive sync keeps working
        // without re-prompting on every launch.
        'access_type': 'offline',
        'prompt': 'consent',
      });

      if (!await launchUrl(authUrl)) {
        throw const GoogleSignInSetupException(
            'Could not open the browser for Google sign-in.');
      }

      final params = await _awaitRedirect(server, state);

      final error = params['error'];
      if (error != null) {
        throw GoogleSignInSetupException('Google sign-in failed: $error');
      }
      final code = params['code'];
      if (code == null) {
        throw const GoogleSignInSetupException(
            'Google sign-in did not return an authorization code.');
      }

      return _exchangeCode(
        code: code,
        verifier: verifier,
        redirectUri: redirectUri,
      );
    } finally {
      await server.close(force: true);
    }
  }

  /// Waits for the browser redirect carrying the code, ignoring unrelated
  /// requests such as /favicon.ico.
  Future<Map<String, String>> _awaitRedirect(
      HttpServer server, String expectedState) async {
    await for (final request in server
        .timeout(const Duration(minutes: 5), onTimeout: (sink) => sink.close())) {
      final params = request.uri.queryParameters;
      final isRedirect =
          params.containsKey('code') || params.containsKey('error');

      request.response.statusCode = isRedirect ? 200 : 404;
      if (isRedirect) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<html><body style="font-family: sans-serif">'
          '<h3>Signed in</h3>'
          '<p>You can close this window and return to Papers.</p>'
          '</body></html>',
        );
      }
      await request.response.close();

      if (isRedirect) {
        if (params['state'] != expectedState) {
          throw const GoogleSignInSetupException(
              'Google sign-in failed: state mismatch.');
        }
        return params;
      }
    }
    throw const GoogleSignInSetupException(
        'Google sign-in timed out — the browser never returned.');
  }

  Future<_TokenResponse> _exchangeCode({
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    final response = await http.post(Uri.parse(_tokenEndpoint), body: {
      'client_id': DesktopOAuthConfig.clientId,
      if (DesktopOAuthConfig.clientSecret.isNotEmpty)
        'client_secret': DesktopOAuthConfig.clientSecret,
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': redirectUri,
    });

    if (response.statusCode != 200) {
      throw GoogleSignInSetupException(
          'Google token exchange failed (${response.statusCode}): '
          '${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _TokenResponse(
      accessToken: json['access_token'] as String,
      idToken: json['id_token'] as String?,
      refreshToken: json['refresh_token'] as String?,
      expiry: DateTime.now()
          .add(Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 3600)),
    );
  }

  Future<String?> _refreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);
    if (refreshToken == null || !DesktopOAuthConfig.isConfigured) return null;

    final response = await http.post(Uri.parse(_tokenEndpoint), body: {
      'client_id': DesktopOAuthConfig.clientId,
      if (DesktopOAuthConfig.clientSecret.isNotEmpty)
        'client_secret': DesktopOAuthConfig.clientSecret,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    });

    if (response.statusCode != 200) {
      // Refresh token revoked or expired — force a fresh sign-in next time.
      await prefs.remove(_refreshTokenKey);
      return null;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _accessToken = json['access_token'] as String;
    _accessTokenExpiry = DateTime.now()
        .add(Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 3600));
    return _accessToken;
  }

  String _randomUrlSafeString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }
}

class _TokenResponse {
  final String accessToken;
  final String? idToken;
  final String? refreshToken;
  final DateTime expiry;

  const _TokenResponse({
    required this.accessToken,
    required this.idToken,
    required this.refreshToken,
    required this.expiry,
  });
}
