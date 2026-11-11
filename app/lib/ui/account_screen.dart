import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/reminders.dart';
import 'dialogs.dart';
import 'auth_screens.dart';

/// Settings: the signed-in account, and the server the app talks to.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _AccountSection(auth: store.auth),
        const SizedBox(height: 16),
        const _Card(icon: Icons.notifications_none_rounded, child: _NotificationsSection()),
        const SizedBox(height: 16),
        _Card(
          icon: Icons.cloud_outlined,
          child: _ServerSection(store: store),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.icon, this.padding = const EdgeInsets.all(20)});
  final IconData? icon;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null)
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
      ),
    );
  }
}

/// Whether reminders can reach the user, and a way to fix it when they cannot.
class _NotificationsSection extends StatefulWidget {
  const _NotificationsSection();

  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> with WidgetsBindingObserver {
  bool? _on;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from the system settings page: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final on = await Reminders.enabled();
    if (mounted) setState(() => _on = on);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = _on;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Notifications', style: theme.textTheme.titleMedium)),
            if (on != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: on ? const Color(0x2230A46C) : scheme.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  on ? 'On' : 'Off',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: on ? const Color(0xFF218358) : scheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          on == false
              ? 'Reminders cannot reach you while notifications are off.'
              : 'Used only for the reminders you set on saved posts.',
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 16),
        if (on == false)
          FilledButton.tonal(
            onPressed: () async {
              await Reminders.ensurePermission(context);
              await _check();
            },
            child: const Text('Turn on notifications'),
          )
        else
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: Reminders.openSettings,
            child: const Text('Notification settings'),
          ),
      ],
    );
  }
}

/// Profile, password, sign out and delete account.
class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.auth});
  final Auth auth;

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _editName(BuildContext context, AuthUser user) async {
    final name = await promptText(
      context,
      title: 'Your name',
      hint: 'Name',
      initial: user.name,
      capitalization: TextCapitalization.words,
    );
    if (name != null && name.trim().isNotEmpty) await auth.updateName(name);
  }

  Future<void> _changePassword(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(auth: auth),
    );
    if (changed == true && context.mounted) _snack(context, 'Password changed');
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await confirm(
      context,
      icon: Icons.logout_rounded,
      title: 'Sign out?',
      message: 'Your saved posts stay on this phone and are here when you sign back in.',
      confirmLabel: 'Sign out',
    );
    if (ok != true || !context.mounted) return;
    // Back to the root first; signing out swaps it for the sign-in screen.
    Navigator.of(context).popUntil((r) => r.isFirst);
    await auth.signOut();
  }

  Future<void> _delete(BuildContext context, AuthUser user) async {
    final ok = await confirm(
      context,
      icon: Icons.person_remove_outlined,
      title: user.isDemo ? 'Leave the demo account?' : 'Delete your account?',
      message: user.isDemo
          ? 'The demo account cannot be deleted, so this signs you out. Your saved posts stay on this phone.'
          : 'The account ${user.email} is removed from this phone and cannot be recovered. '
                'Your saved posts are not deleted.',
      confirmLabel: user.isDemo ? 'Sign out' : 'Delete account',
      destructive: !user.isDemo,
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await auth.deleteAccount();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth,
    builder: (context, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final user = auth.user;
      if (user == null) return const SizedBox.shrink();

      Widget row(IconData icon, String label, VoidCallback onTap, {Color? color, String? value}) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(icon, color: color ?? scheme.onSurfaceVariant),
        title: Text(label, style: TextStyle(color: color)),
        trailing: value != null
            ? Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
            : Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        onTap: onTap,
      );

      return _Card(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: scheme.primary,
                    child: Text(
                      user.initial,
                      style: TextStyle(color: scheme.onPrimary, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name.isEmpty ? 'Your account' : user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (user.isDemo)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'You are on the demo account. Accounts are kept on this phone for now and do not sync.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                ),
              ),
            row(Icons.badge_outlined, 'Name', () => _editName(context, user), value: user.name),
            if (!user.isDemo) row(Icons.lock_outline_rounded, 'Change password', () => _changePassword(context)),
            row(Icons.logout_rounded, 'Sign out', () => _signOut(context)),
            row(Icons.delete_outline_rounded, 'Delete account', () => _delete(context, user), color: scheme.error),
          ],
        ),
      );
    },
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.auth});
  final Auth auth;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await widget.auth.changePassword(current: _current.text, next: _next.text);
      if (mounted) Navigator.pop(context, true);
    } on AuthError catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PasswordField(
              controller: _current,
              hint: 'Current password',
              textInputAction: TextInputAction.next,
              validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null,
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _next,
              hint: 'New password',
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              validator: Auth.validatePassword,
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _confirm,
              hint: 'Repeat new password',
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) => v == _next.text ? null : 'The two passwords do not match',
              onSubmitted: _save,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: _save, child: const Text('Change')),
    ],
  );
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
          'The AI (descriptions, folders, search) runs on your Stash server. '
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
                        ? 'Connected. New saves will get descriptions and suggestions.'
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
