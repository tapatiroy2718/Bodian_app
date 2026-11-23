import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import 'auth_gate.dart';

String _roleTitle(String role) => role == 'vendor' ? 'Vendor' : 'Customer';

String? _validateEmail(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter your email';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'Enter a valid email';
  return null;
}

String? _validatePassword(String? v) {
  if ((v ?? '').length < 6) return 'Password must be at least 6 characters';
  return null;
}

class _AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _AuthScaffold({required this.title, required this.subtitle, required this.children});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            const BodianaLogo(size: 56),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputAction action;
  final VoidCallback? onSubmitted;
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.validator,
    this.action = TextInputAction.done,
    this.onSubmitted,
  });
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      textInputAction: widget.action,
      validator: widget.validator ?? _validatePassword,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      autofillHints: const [AutofillHints.password],
      decoration: inputDeco(
        widget.label,
        icon: Icons.lock_outline,
        suffix: IconButton(
          tooltip: _hidden ? 'Show password' : 'Hide password',
          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

class GoogleButton extends StatefulWidget {
  final String role;
  const GoogleButton({super.key, required this.role});
  @override
  State<GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<GoogleButton> {
  bool _busy = false;
  Future<void> _go() async {
    setState(() => _busy = true);
    LoginFlow.pendingRole = widget.role;
    LoginFlow.expectedRole = widget.role;
    try {
      await supa.auth.signInWithOAuth(OAuthProvider.google, redirectTo: AppConfig.authRedirect);
    } catch (e) {
      LoginFlow.pendingRole = null;
      LoginFlow.expectedRole = null;
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _go,
      icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF4285F4))),
      label: const Text('Continue with Google'),
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: const BorderSide(color: Color(0xFFDADCE0)),
        backgroundColor: Colors.white,
      ),
    );
  }
}

Widget _orDivider() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Row(children: [
        Expanded(child: Divider()),
        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: kMuted))),
        Expanded(child: Divider()),
      ]),
    );

// ------------------------------------------------------------------ login

class LoginScreen extends StatefulWidget {
  final String role;
  const LoginScreen({super.key, required this.role});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    LoginFlow.expectedRole = widget.role;
    try {
      await supa.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
    } on AuthException catch (e) {
      LoginFlow.expectedRole = null;
      if (mounted) {
        final msg = e.message.toLowerCase().contains('email not confirmed')
            ? 'Please confirm your email first. Check your inbox for the confirmation link.'
            : e.message.toLowerCase().contains('invalid login')
                ? 'Incorrect email or password.'
                : e.message;
        showSnack(context, msg, error: true);
      }
    } catch (e) {
      LoginFlow.expectedRole = null;
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: '${_roleTitle(widget.role)} login',
      subtitle: widget.role == 'vendor' ? 'Manage your wedding business' : 'Welcome back! Continue planning your wedding',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: _validateEmail,
                decoration: inputDeco('Email', icon: Icons.mail_outline),
              ),
              const SizedBox(height: 14),
              PasswordField(controller: _password, onSubmitted: _login),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _busy ? null : _login,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Log in'),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('New to Bodiana?', style: TextStyle(color: kMuted)),
          TextButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => RegisterScreen(role: widget.role))),
            child: const Text('Create new account'),
          ),
        ]),
        _orDivider(),
        GoogleButton(role: widget.role),
      ],
    );
  }
}

// ------------------------------------------------------------------ register

class RegisterScreen extends StatefulWidget {
  final String role;
  const RegisterScreen({super.key, required this.role});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _agreed = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    if (!_agreed) {
      showSnack(context, 'Please accept the terms and privacy policy.', error: true);
      return;
    }
    setState(() => _busy = true);
    LoginFlow.expectedRole = widget.role;
    try {
      final res = await supa.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        emailRedirectTo: AppConfig.authRedirect,
        data: {
          'role': widget.role,
          'full_name': _name.text.trim(),
          'phone': _phone.text.trim(),
        },
      );
      final identities = res.user?.identities;
      if (res.user != null && identities != null && identities.isEmpty) {
        LoginFlow.expectedRole = null;
        if (mounted) showSnack(context, 'An account with this email already exists. Please log in instead.', error: true);
      } else if (res.session == null) {
        LoginFlow.expectedRole = null;
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Confirm your email'),
              content: Text('We sent a confirmation link to ${_email.text.trim()}. '
                  'Open it on this phone, then log in.'),
              actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
            ),
          );
          if (mounted) Navigator.pop(context);
        }
      }
      // With a session, the auth gate takes over automatically.
    } on AuthException catch (e) {
      LoginFlow.expectedRole = null;
      if (mounted) {
        final msg = e.message.toLowerCase().contains('already registered')
            ? 'An account with this email already exists. Please log in instead.'
            : e.message;
        showSnack(context, msg, error: true);
      }
    } catch (e) {
      LoginFlow.expectedRole = null;
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Create ${_roleTitle(widget.role).toLowerCase()} account',
      subtitle: widget.role == 'vendor'
          ? 'Start receiving wedding enquiries'
          : 'Start planning your Bengali wedding',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                decoration: inputDeco(widget.role == 'vendor' ? 'Owner name' : 'Your name', icon: Icons.person_outline),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: _validateEmail,
                decoration: inputDeco('Email', icon: Icons.mail_outline),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: inputDeco('Phone number (optional)', icon: Icons.phone_outlined),
              ),
              const SizedBox(height: 14),
              PasswordField(controller: _password, action: TextInputAction.next),
              const SizedBox(height: 14),
              PasswordField(
                controller: _confirm,
                label: 'Confirm password',
                validator: (v) => v != _password.text ? 'Passwords do not match' : null,
                onSubmitted: _register,
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('I agree to the Terms of Service and Privacy Policy', style: TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _busy ? null : _register,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Create account'),
        ),
        _orDivider(),
        GoogleButton(role: widget.role),
      ],
    );
  }
}

// ------------------------------------------------------------------ password reset

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await supa.auth.resetPasswordForEmail(_email.text.trim(), redirectTo: AppConfig.authRedirect);
    });
    if (mounted) setState(() {
      _busy = false;
      _sent = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Forgot password',
      subtitle: 'We will email you a link to set a new password',
      children: [
        if (_sent)
          const AppCard(
            color: kCream,
            child: Text('Check your inbox. Open the reset link on this phone to choose a new password.'),
          )
        else ...[
          Form(
            key: _form,
            child: TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
              decoration: inputDeco('Email', icon: Icons.mail_outline),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _busy ? null : _send, child: const Text('Send reset link')),
        ],
      ],
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await supa.auth.updateUser(UserAttributes(password: _password.text));
    }, success: 'Password updated');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Set a new password',
      subtitle: 'Choose a password with at least 6 characters',
      children: [
        Form(
          key: _form,
          child: Column(children: [
            PasswordField(controller: _password, label: 'New password', action: TextInputAction.next),
            const SizedBox(height: 14),
            PasswordField(
              controller: _confirm,
              label: 'Confirm new password',
              validator: (v) => v != _password.text ? 'Passwords do not match' : null,
              onSubmitted: _save,
            ),
          ]),
        ),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _busy ? null : _save, child: const Text('Save password')),
      ],
    );
  }
}
