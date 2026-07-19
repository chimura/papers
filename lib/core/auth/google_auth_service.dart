import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'desktop_google_auth.dart';

/// True on platforms where the google_sign_in plugin has no implementation
/// and the browser-based loopback flow is used instead.
bool get useDesktopGoogleAuth =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux);

/// google_sign_in v7 requires a single initialize() call before any other
/// method. Shared by the sign-in service and the Drive HTTP client.
Future<void> ensureGoogleSignInInitialized() => _initialization ??=
    GoogleSignIn.instance.initialize();
Future<void>? _initialization;

class GoogleAuthService {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  GoogleAuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithGoogle() async {
    if (useDesktopGoogleAuth) {
      return DesktopGoogleAuth.instance.signIn();
    }

    await ensureGoogleSignInInitialized();
    final googleUser = await _googleSignIn.authenticate(
      scopeHint: [
        'email',
        'https://www.googleapis.com/auth/drive.file',
      ],
    );

    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    return _auth.signInWithCredential(credential);
  }

  /// Local-only session without a Google account; Drive sync stays disabled
  /// until the user signs in with Google from Settings.
  Future<UserCredential> signInAnonymously() => _auth.signInAnonymously();

  Future<void> signOut() async {
    if (useDesktopGoogleAuth) {
      await Future.wait([
        _auth.signOut(),
        DesktopGoogleAuth.instance.signOut(),
      ]);
      return;
    }

    await ensureGoogleSignInInitialized();
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }
}
