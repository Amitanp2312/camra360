import 'package:supabase_flutter/supabase_flutter.dart';

/// A sign-in or sign-up failure with a message safe to show in the UI.
class AuthFailure implements Exception {
  AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Email/password auth. Session persistence is handled by supabase_flutter
/// (SharedPreferences) because [Supabase.initialize] is called with the
/// default [FlutterAuthClientOptions.persistSession] of true.
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (error) {
      throw AuthFailure('Could not sign in: $error');
    }
  }

  /// Returns true when Supabase created the user but will not start a session
  /// until the address is confirmed.
  Future<bool> signUp({required String email, required String password}) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      return response.session == null;
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (error) {
      throw AuthFailure('Could not create the account: $error');
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (error) {
      throw AuthFailure('Could not sign out: $error');
    }
  }
}
