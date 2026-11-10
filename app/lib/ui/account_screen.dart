import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../data/store.dart';
import '../services/api.dart';

/// Optional account for syncing between devices. Everything works without one.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.store});
  final Store store;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;

  Store get store => widget.store;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    String? message;
    try {
      message = await action();
    } on AuthException catch (e) {
      message = e.message;
    } catch (_) {
      message = 'Could not reach the sync server. Check your connection and try again.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _message = message;
      });
    }
  }

  Future<String?> _syncNow() async {
    await store.sync.sync();
    await store.reload();
    return 'Synced just now';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4);
    final sync = store.sync;
    final user = sync.user;

    final List<Widget> body;
    if (!sync.enabled) {
      body = [
        Text('Sync between devices', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Not available in this version. Your saves are stored on this phone only.', style: muted),
      ];
    } else if (user == null) {
      body = [
        Text('Sync between devices', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Optional. Without an account, your saves stay on this device.', style: muted),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(hintText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(hintText: 'Password'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await sync.signIn(_email.text.trim(), _password.text);
                  return _syncNow();
                }),
          child: const Text('Sign in'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  final signedIn = await sync.signUp(_email.text.trim(), _password.text);
                  return signedIn ? _syncNow() : 'Check your inbox to confirm your email, then sign in.';
                }),
          child: const Text('Create account'),
        ),
      ];
    } else {
      body = [
        Text(user.email ?? 'Signed in', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Folders and saved posts sync automatically when the app is open.', style: muted),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : () => _run(_syncNow), child: const Text('Sync now')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await sync.signOut();
                  return null;
                }),
          child: const Text('Sign out'),
        ),
      ];
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _Card(
            icon: Icons.cloud_outlined,
            child: _ServerSection(store: store),
          ),
          const SizedBox(height: 16),
          _Card(
            icon: Icons.sync_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...body,
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_message!, textAlign: TextAlign.center, style: muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.child});
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 22, color: scheme.onPrimaryContainer),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Where previews and folder suggestions come from. Lets one build of the app
/// be pointed at any deployment of the backend.
class _ServerSection extends StatefulWidget {
  const _ServerSection({required this.store});
  final Store store;

  @override
  State<_ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends State<_ServerSection> {
  late final _url = TextEditingController(text: widget.store.api.baseUrl);
  bool _busy = false;
  bool? _ok;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _ok = null;
    });
    final store = widget.store;
    store.api.baseUrl = _url.text;
    _url.text = store.api.baseUrl;
    await store.repo.setKv(backendUrlKey, _url.text);
    final ok = await store.api.ping();
    if (ok) await store.background();
    if (mounted) {
      setState(() {
        _busy = false;
        _ok = ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Server', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Previews and smart folder suggestions come from your Stash server. '
          'Saving still works without it, into the last used folder.',
          style: muted,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(hintText: 'https://your-server.example.com'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: _busy ? null : _save, child: Text(_busy ? 'Checking…' : 'Save and test')),
        if (_ok != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                Icon(
                  _ok! ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  size: 20,
                  color: _ok! ? const Color(0xFF30A46C) : scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _ok!
                        ? 'Connected. New saves will get previews and suggestions.'
                        : 'No answer from this address. Check it and that the server is running.',
                    style: muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
