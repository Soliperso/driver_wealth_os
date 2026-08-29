import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/hero_form_scaffold.dart';
import '../application/auth_gateway.dart';
import '../domain/password_policy.dart';

/// Every way into an account: signing in, signing up, and getting back in
/// after forgetting a password.
///
/// One screen rather than five routes, because the app swaps top-level screens
/// by state rather than navigating — the signed-in state arrives on the
/// gateway's stream and `app.dart` replaces this whole widget. A `Navigator`
/// here would only add a back stack that the sign-in event then invalidates.
///
/// This screen exists because the alternative — the anonymous session the app
/// used to create silently — meant a reinstall, a new phone, or two weeks away
/// from the app destroyed the driver's history with no way to recover it.
class AuthFlowScreen extends StatefulWidget {
  const AuthFlowScreen({
    super.key,
    required this.gateway,
    this.onSignUpName,
  });

  final AuthGateway gateway;

  /// Reports the name given at signup, before the account is created.
  ///
  /// Announced early on purpose: the signed-in state arrives on a stream that
  /// the app reacts to immediately, so a name handed over afterwards would
  /// race the screen being torn down.
  final ValueChanged<String>? onSignUpName;

  @override
  State<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

enum _Step { login, signUp, forgotPassword, resetCode, codeEmail, codeVerify }

class _AuthFlowScreenState extends State<AuthFlowScreen> {
  /// Shared across steps: an address typed to sign in is the same address the
  /// reset code should go to.
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _resetCode = TextEditingController();
  final _newPassword = TextEditingController();

  /// One key per step. A single shared key would be attached to two forms at
  /// once while the switcher cross-fades.
  final _formKeys = {
    for (final step in _Step.values) step: GlobalKey<FormState>(),
  };

  var _step = _Step.login;
  var _busy = false;
  var _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _code.dispose();
    _resetCode.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HeroFormScaffold(
    eyebrow: switch (_step) {
      _Step.signUp => 'YOUR PROFIT, MADE CLEAR',
      _Step.forgotPassword || _Step.resetCode => 'ACCOUNT RECOVERY',
      _ => 'YOUR NUMBERS, ANYWHERE',
    },
    headline: switch (_step) {
      _Step.signUp => 'Start keeping\nmore of it.',
      _Step.forgotPassword || _Step.resetCode => 'Get back into\nyour account.',
      _ => 'Sign in to keep\nyour history safe.',
    },
    subcopy: switch (_step) {
      _Step.signUp =>
        'Every session you log becomes a clear view of what you earned, what '
            'it cost, and what you actually kept.',
      _Step.forgotPassword || _Step.resetCode =>
        'We will email you a 6-digit code. Enter it here and choose a new '
            'password — your records are untouched.',
      _ =>
        'Your sessions, goals and expenses stay with your account — so a new '
            'phone or a reinstall does not cost you your records.',
    },
    // The pitch belongs on the screen for someone who has not decided yet. A
    // driver signing back in has already seen it.
    aside: _step == _Step.signUp ? const ProfitPreview() : null,
    card: AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: KeyedSubtree(
        key: ValueKey(_step),
        child: switch (_step) {
          _Step.login => _login(),
          _Step.signUp => _signUp(),
          _Step.forgotPassword => _forgotPassword(),
          _Step.resetCode => _resetPassword(),
          _Step.codeEmail => _codeEmail(),
          _Step.codeVerify => _codeVerify(),
        },
      ),
    ),
  );

  // ---------------------------------------------------------------- steps

  Widget _login() => _Card(
    formKey: _formKeys[_Step.login]!,
    title: 'Sign in',
    subtitle: 'Welcome back.',
    children: [
      _emailField(const ValueKey('login-email-field')),
      Space.gapMd,
      _passwordField(
        key: const ValueKey('login-password-field'),
        controller: _password,
        label: 'Password',
        // Deliberately not the signup policy: an older account may predate the
        // current rules, and refusing to even attempt the sign-in would lock
        // its owner out over a rule they never agreed to.
        validator: (value) => (value ?? '').isEmpty ? 'Enter your password' : null,
        onSubmitted: _signIn,
      ),
      _errorRow(),
      Space.gapMd,
      _submit(
        key: const ValueKey('login-submit'),
        label: 'Sign in',
        busyLabel: 'Signing in…',
        onPressed: _signIn,
      ),
      Space.gapSm,
      // Stacked rather than side by side: two links on one row overflow at
      // phone width, and the wrap that avoids it looks like a mistake.
      _link(
        key: const ValueKey('go-forgot-password'),
        label: 'Forgot password?',
        step: _Step.forgotPassword,
      ),
      const Divider(height: Space.xl),
      _link(
        key: const ValueKey('go-code-sign-in'),
        label: 'Email me a code instead',
        step: _Step.codeEmail,
      ),
      Space.gapXs,
      _link(
        key: const ValueKey('go-create-account'),
        label: 'New here? Create an account',
        step: _Step.signUp,
      ),
    ],
  );

  Widget _signUp() => _Card(
    formKey: _formKeys[_Step.signUp]!,
    title: 'Create your account',
    subtitle: 'Takes about a minute.',
    children: [
      TextFormField(
        key: const ValueKey('sign-up-name-field'),
        controller: _name,
        enabled: !_busy,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.givenName],
        // The name is greeted on every Today screen. A pasted paragraph would
        // break that line rather than personalise it.
        inputFormatters: [LengthLimitingTextInputFormatter(24)],
        decoration: const InputDecoration(
          labelText: 'First name',
          hintText: 'Ahmed',
          prefixIcon: Icon(Icons.person_outline_rounded),
        ),
        validator: (value) => (value ?? '').trim().isEmpty
            ? 'Enter your name so we know what to call you'
            : null,
      ),
      Space.gapMd,
      _emailField(const ValueKey('sign-up-email-field')),
      Space.gapMd,
      _passwordField(
        key: const ValueKey('sign-up-password-field'),
        controller: _password,
        label: 'Password',
        helper: PasswordPolicy.requirement,
        validator: PasswordPolicy.validate,
        onSubmitted: _createAccount,
      ),
      _errorRow(),
      Space.gapMd,
      _submit(
        key: const ValueKey('sign-up-submit'),
        label: 'Create account',
        busyLabel: 'Creating…',
        onPressed: _createAccount,
      ),
      Space.gapSm,
      _link(
        key: const ValueKey('go-sign-in'),
        label: 'I already have an account',
        step: _Step.login,
      ),
    ],
  );

  Widget _forgotPassword() => _Card(
    formKey: _formKeys[_Step.forgotPassword]!,
    title: 'Forgot your password?',
    subtitle: 'We will email you a code to reset it.',
    children: [
      _emailField(const ValueKey('forgot-email-field')),
      _errorRow(),
      Space.gapMd,
      _submit(
        key: const ValueKey('forgot-submit'),
        label: 'Email me a reset code',
        busyLabel: 'Sending…',
        onPressed: _sendReset,
      ),
      Space.gapSm,
      _link(
        key: const ValueKey('cancel-forgot-password'),
        label: 'Back to sign in',
        step: _Step.login,
      ),
    ],
  );

  Widget _resetPassword() => _Card(
    formKey: _formKeys[_Step.resetCode]!,
    title: 'Choose a new password',
    subtitle: 'Sent to ${_email.text.trim()}.',
    children: [
      _codeField(const ValueKey('reset-code-field'), _resetCode),
      Space.gapMd,
      _passwordField(
        key: const ValueKey('reset-password-field'),
        controller: _newPassword,
        label: 'New password',
        helper: PasswordPolicy.requirement,
        validator: PasswordPolicy.validate,
        onSubmitted: _resetPasswordSubmit,
      ),
      _errorRow(),
      Space.gapMd,
      _submit(
        key: const ValueKey('reset-submit'),
        label: 'Set new password',
        busyLabel: 'Saving…',
        onPressed: _resetPasswordSubmit,
      ),
      Space.gapSm,
      _link(
        key: const ValueKey('resend-reset-code'),
        label: 'Send another code',
        step: _Step.forgotPassword,
      ),
    ],
  );

  Widget _codeEmail() => _Card(
    formKey: _formKeys[_Step.codeEmail]!,
    title: 'Sign in with a code',
    subtitle: 'We will email you a 6-digit code. No password needed.',
    children: [
      _emailField(const ValueKey('sign-in-email-field')),
      _errorRow(),
      Space.gapMd,
      _submit(
        key: const ValueKey('send-code-button'),
        label: 'Email me a code',
        busyLabel: 'Sending…',
        onPressed: _sendCode,
      ),
      Space.gapSm,
      _link(
        key: const ValueKey('cancel-code-sign-in'),
        label: 'Use my password instead',
        step: _Step.login,
      ),
      Space.gapMd,
      Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              'Only your earnings data. We never ask for bank details.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _codeVerify() => _Card(
    formKey: _formKeys[_Step.codeVerify]!,
    title: 'Enter your code',
    subtitle: 'Sent to ${_email.text.trim()}.',
    children: [
      _codeField(const ValueKey('sign-in-code-field'), _code),
      _errorRow(),
      Space.gapMd,
      _submit(
        key: const ValueKey('verify-code-button'),
        label: 'Sign in',
        busyLabel: 'Checking…',
        onPressed: _verifyCode,
      ),
      Space.gapSm,
      _link(
        key: const ValueKey('change-email-button'),
        label: 'Use a different email',
        step: _Step.codeEmail,
        onTap: _code.clear,
      ),
    ],
  );

  // ---------------------------------------------------------------- pieces

  Widget _emailField(Key key) => TextFormField(
    key: key,
    controller: _email,
    enabled: !_busy,
    keyboardType: TextInputType.emailAddress,
    textInputAction: TextInputAction.next,
    autocorrect: false,
    autofillHints: const [AutofillHints.email],
    decoration: const InputDecoration(
      labelText: 'Email address',
      hintText: 'you@example.com',
      prefixIcon: Icon(Icons.mail_outline_rounded),
    ),
    validator: _validateEmail,
  );

  Widget _passwordField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required FormFieldValidator<String> validator,
    required VoidCallback onSubmitted,
    String? helper,
  }) => TextFormField(
    key: key,
    controller: controller,
    enabled: !_busy,
    obscureText: _obscure,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: TextInputAction.done,
    autofillHints: const [AutofillHints.password],
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        key: const ValueKey('toggle-password-visibility'),
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: Icon(
          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        tooltip: _obscure ? 'Show password' : 'Hide password',
      ),
    ),
    validator: validator,
    onFieldSubmitted: (_) => onSubmitted(),
  );

  Widget _codeField(Key key, TextEditingController controller) => TextFormField(
    key: key,
    controller: controller,
    enabled: !_busy,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.next,
    autofillHints: const [AutofillHints.oneTimeCode],
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ],
    decoration: const InputDecoration(
      labelText: '6-digit code',
      prefixIcon: Icon(Icons.pin_outlined),
    ),
    validator: (value) => (value ?? '').trim().length == 6
        ? null
        : 'Enter the 6-digit code from your email',
  );

  Widget _submit({
    required Key key,
    required String label,
    required String busyLabel,
    required VoidCallback onPressed,
  }) => FilledButton(
    key: key,
    onPressed: _busy ? null : onPressed,
    child: Text(_busy ? busyLabel : label),
  );

  /// Moves to another step, clearing the error so a message about the last
  /// screen does not follow the driver onto the next one.
  Widget _link({
    required Key key,
    required String label,
    required _Step step,
    VoidCallback? onTap,
  }) => TextButton(
    key: key,
    onPressed: _busy
        ? null
        : () {
            onTap?.call();
            setState(() {
              _step = step;
              _error = null;
            });
          },
    child: Text(label),
  );

  Widget _errorRow() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: Space.md),
          child: _ErrorText(message: _error!),
        );

  // ---------------------------------------------------------------- actions

  static String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Enter your email address to continue';
    // Deliberately loose. The authoritative check is whether the code arrives;
    // a stricter pattern here would only reject valid, unusual addresses.
    final looksLikeEmail = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email);
    return looksLikeEmail ? null : 'That email address does not look right';
  }

  /// Runs one gateway call with the busy flag and error handling every step
  /// shares, then moves to [next] if one was given.
  ///
  /// Signing in and creating an account name no next step: the session lands on
  /// the gateway's stream and the app replaces this screen entirely.
  Future<void> _attempt(
    _Step from,
    Future<void> Function() action, {
    _Step? next,
  }) async {
    if (!_formKeys[from]!.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted || next == null) return;
      setState(() => _step = next);
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _signIn() => unawaited(
    _attempt(
      _Step.login,
      () => widget.gateway.signIn(
        email: _email.text.trim(),
        password: _password.text,
      ),
    ),
  );

  void _createAccount() {
    final name = _name.text.trim();
    unawaited(
      _attempt(_Step.signUp, () async {
        // Handed over before the account exists, so it is already waiting when
        // the sign-in event arrives and this screen is torn down.
        widget.onSignUpName?.call(name);
        await widget.gateway.signUp(
          email: _email.text.trim(),
          password: _password.text,
          name: name,
        );
      }),
    );
  }

  void _sendReset() => unawaited(
    _attempt(
      _Step.forgotPassword,
      () => widget.gateway.sendPasswordReset(_email.text.trim()),
      next: _Step.resetCode,
    ),
  );

  void _resetPasswordSubmit() => unawaited(
    _attempt(_Step.resetCode, () async {
      // The code buys a session; the session is what makes the change
      // permitted. Both have to succeed or the driver is left signed in with
      // the old password still set.
      await widget.gateway.verifyPasswordReset(
        email: _email.text.trim(),
        code: _resetCode.text.trim(),
      );
      await widget.gateway.updatePassword(_newPassword.text);
    }),
  );

  void _sendCode() => unawaited(
    _attempt(
      _Step.codeEmail,
      () => widget.gateway.sendCode(_email.text.trim()),
      next: _Step.codeVerify,
    ),
  );

  void _verifyCode() => unawaited(
    _attempt(
      _Step.codeVerify,
      () => widget.gateway.verifyCode(
        email: _email.text.trim(),
        code: _code.text.trim(),
      ),
    ),
  );
}

/// The card body every step shares: a title, a line of context, and fields.
class _Card extends StatelessWidget {
  const _Card({
    required this.formKey,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final GlobalKey<FormState> formKey;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          Space.gapXs,
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          Space.gapXl,
          ...children,
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('sign-in-error'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 16, color: colors.error),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.error),
          ),
        ),
      ],
    );
  }
}
