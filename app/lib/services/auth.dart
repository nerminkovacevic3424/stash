import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/repo.dart';

/// Who is signed in.
class AuthUser {
  const AuthUser({required this.email, required this.name});
  final String email;
  final String name;

  bool get isDemo => email == Auth.demoEmail;
  String get initial => (name.isNotEmpty ? name : email).substring(0, 1).toUpperCase();
}

/// Thrown with a message that can be shown to the user as is.
class AuthError implements Exception {
  const AuthError(this.message);
  final String message;
}

/// PLACEHOLDER sign-in that lives entirely on this phone.
///
/// There is no server behind it: accounts are rows in the local database and
/// a built-in demo account always works. It exists so the sign-in screens and
/// account settings can be built and used before a real identity service
/// (Firebase Auth, Supabase Auth) is connected. When that happens, replace
/// the bodies of [signIn], [signUp], [changePassword] and [deleteAccount];
/// the screens only depend on this class's methods.
///
/// It protects nothing: anyone holding the phone can use the demo account.
class Auth extends ChangeNotifier {
  Auth(this.repo);
  final Repo repo;

  /// The built-in account. Shown on the sign-in screen behind "Use demo account".
  static const demoEmail = 'demo@stash.app';
  static const demoPassword = 'stash-demo';
  static const _demoName = 'Demo';

  static const _sessionKey = 'auth_user';
  static const _accountsKey = 'auth_accounts';

  AuthUser? _user;
  AuthUser? get user => _user;
  bool get signedIn => _user != null;

  /// Restores the session saved by the last launch.
  Future<void> load() async {
    final raw = await repo.kv(_sessionKey);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _user = AuthUser(email: j['email'] as String, name: j['name'] as String? ?? '');
    } catch (_) {
      _user = null;
    }
  }

  static String? validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v) ? null : 'That does not look like an email';
  }

  static String? validatePassword(String? value) => (value ?? '').length >= 6 ? null : 'Use at least 6 characters';

  Future<Map<String, dynamic>> _accounts() async {
    final raw = await repo.kv(_accountsKey);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // Passwords of local accounts are kept only as a salted hash.
  static String _hash(String password, String salt) => sha256.convert(utf8.encode('$salt:$password')).toString();

  static String _newSalt() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _start(AuthUser user) async {
    _user = user;
    await repo.setKv(_sessionKey, jsonEncode({'email': user.email, 'name': user.name}));
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    email = email.trim().toLowerCase();
    if (email == demoEmail && password == demoPassword) {
      return _start(const AuthUser(email: demoEmail, name: _demoName));
    }
    final account = (await _accounts())[email];
    if (account is! Map || _hash(password, account['salt'] as String) != account['hash']) {
      throw const AuthError('Wrong email or password');
    }
    await _start(AuthUser(email: email, name: account['name'] as String? ?? ''));
  }

  Future<void> signInWithDemo() => signIn(demoEmail, demoPassword);

  Future<void> signUp({required String name, required String email, required String password}) async {
    email = email.trim().toLowerCase();
    final accounts = await _accounts();
    if (email == demoEmail || accounts.containsKey(email)) {
      throw const AuthError('An account with this email already exists. Sign in instead.');
    }
    final salt = _newSalt();
    accounts[email] = {'name': name.trim(), 'salt': salt, 'hash': _hash(password, salt)};
    await repo.setKv(_accountsKey, jsonEncode(accounts));
    await _start(AuthUser(email: email, name: name.trim()));
  }

  Future<void> signOut() async {
    _user = null;
    await repo.setKv(_sessionKey, null);
    notifyListeners();
  }

  Future<void> updateName(String name) async {
    final u = _user;
    if (u == null) return;
    name = name.trim();
    if (!u.isDemo) {
      final accounts = await _accounts();
      final account = accounts[u.email];
      if (account is Map) {
        account['name'] = name;
        await repo.setKv(_accountsKey, jsonEncode(accounts));
      }
    }
    await _start(AuthUser(email: u.email, name: name));
  }

  Future<void> changePassword({required String current, required String next}) async {
    final u = _user;
    if (u == null) return;
    if (u.isDemo) throw const AuthError('The demo account has a fixed password.');
    final accounts = await _accounts();
    final account = accounts[u.email];
    if (account is! Map || _hash(current, account['salt'] as String) != account['hash']) {
      throw const AuthError('Your current password is not right');
    }
    final salt = _newSalt();
    account['salt'] = salt;
    account['hash'] = _hash(next, salt);
    await repo.setKv(_accountsKey, jsonEncode(accounts));
  }

  /// Removes the account and signs out. Saved posts are not touched.
  Future<void> deleteAccount() async {
    final u = _user;
    if (u == null) return;
    if (!u.isDemo) {
      final accounts = await _accounts()
        ..remove(u.email);
      await repo.setKv(_accountsKey, jsonEncode(accounts));
    }
    await signOut();
  }
}
