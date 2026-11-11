import 'package:flutter/material.dart';

import '../services/auth.dart';
import 'logo.dart';

/// Password field with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.hint = 'Password',
    this.validator,
    this.onSubmitted,
    this.autofillHints = const [AutofillHints.password],
    this.textInputAction = TextInputAction.done,
  });
  final TextEditingController controller;
  final String hint;
  final FormFieldValidator<String>? validator;
  final VoidCallback? onSubmitted;
  final Iterable<String> autofillHints;
  final TextInputAction textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _hidden,
    autofillHints: widget.autofillHints,
    textInputAction: widget.textInputAction,
    validator: widget.validator,
    onFieldSubmitted: (_) => widget.onSubmitted?.call(),
    decoration: InputDecoration(
      hintText: widget.hint,
      suffixIcon: IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}

/// Shared frame for the three auth pages: logo, title, a line of help, the form.
class _AuthPage extends StatelessWidget {
  const _AuthPage({required this.title, required this.subtitle, required this.children, this.back = false});
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool back;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: back ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!back) ...[
                    const Align(alignment: Alignment.centerLeft, child: StashLogo(size: 56)),
                    const SizedBox(height: 28),
                  ],
                  Text(
                    title,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox(height: 20);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message!, style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }
}

/// Runs an auth call from a form: validates, shows a spinner, surfaces errors.
mixin _Submitting<T extends StatefulWidget> on State<T> {
  final formKey = GlobalKey<FormState>();
  bool busy = false;
  String? error;

  Future<void> submit(Future<void> Function() action) async {
    if (busy || !(formKey.currentState?.validate() ?? false)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on AuthError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget spinnerOr(String label) =>
      busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(label);
}

/// First screen for someone who is not signed in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth});
  final Auth auth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> with _Submitting {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _signIn() => submit(() => widget.auth.signIn(_email.text, _password.text));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _AuthPage(
      title: 'Welcome back',
      subtitle: 'Sign in to your Stash.',
      children: [
        Form(
          key: formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: Auth.validateEmail,
                  decoration: const InputDecoration(hintText: 'Email'),
                ),
                const SizedBox(height: 12),
                PasswordField(
                  controller: _password,
                  validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                  onSubmitted: _signIn,
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => ForgotPasswordScreen(email: _email.text)),
            ),
            child: const Text('Forgot password?'),
          ),
        ),
        _ErrorText(error),
        FilledButton(onPressed: busy ? null : _signIn, child: spinnerOr('Sign in')),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: busy ? null : () => submitDemo(), child: const Text('Use demo account')),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('New here?', style: TextStyle(color: scheme.onSurfaceVariant)),
            TextButton(
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SignUpScreen(auth: widget.auth))),
              child: const Text('Create an account'),
            ),
          ],
        ),
      ],
    );
  }

  /// One tap in: fills the form so it is clear what was used, then signs in.
  Future<void> submitDemo() async {
    _email.text = Auth.demoEmail;
    _password.text = Auth.demoPassword;
    _signIn();
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, required this.auth});
  final Auth auth;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> with _Submitting {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _create() => submit(() async {
    await widget.auth.signUp(name: _name.text, email: _email.text, password: _password.text);
    // Signed in: drop back to the root, which now shows the app.
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  });

  @override
  Widget build(BuildContext context) => _AuthPage(
    back: true,
    title: 'Create your account',
    subtitle: 'It takes a few seconds.',
    children: [
      Form(
        key: formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                decoration: const InputDecoration(hintText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                validator: Auth.validateEmail,
                decoration: const InputDecoration(hintText: 'Email'),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _password,
                hint: 'Password (6 or more characters)',
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: Auth.validatePassword,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _confirm,
                hint: 'Repeat password',
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => v == _password.text ? null : 'The two passwords do not match',
                onSubmitted: _create,
              ),
            ],
          ),
        ),
      ),
      _ErrorText(error),
      FilledButton(onPressed: busy ? null : _create, child: spinnerOr('Create account')),
      const SizedBox(height: 12),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('I already have an account')),
    ],
  );
}

/// Password reset needs a server that can send email. Until one is connected
/// this page says so plainly instead of pretending a link was sent.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});
  final String email;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _formKey = GlobalKey<FormState>();
  bool _asked = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _AuthPage(
      back: true,
      title: 'Reset your password',
      subtitle: 'Enter the email you signed up with.',
      children: [
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            validator: Auth.validateEmail,
            decoration: const InputDecoration(hintText: 'Email'),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) setState(() => _asked = true);
          },
          child: const Text('Send reset link'),
        ),
        if (_asked)
          Container(
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Reset emails are not connected yet, so nothing was sent. '
                    'Accounts live on this phone for now: use the demo account, or create a new one.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
