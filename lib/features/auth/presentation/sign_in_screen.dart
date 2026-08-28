import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../application/auth_gateway.dart';

/// Two-step email sign-in: address, then the code that was mailed to it.
///
/// This screen exists because the alternative — the anonymous session the app
/// used to create silently — meant a reinstall, a new phone, or two weeks away
/// from the app destroyed the driver's history with no way to recover it.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.gateway});

  final AuthGateway gateway;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

enum _Step { email, code }

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();

  var _step = _Step.email;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          const SoftBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 22),
                            child: _Wordmark(),
                          ),
                          const SizedBox(height: 54),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Text(
                              'YOUR NUMBERS, ANYWHERE',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.25,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Text(
                              'Sign in to keep\nyour history safe.',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: colors.onSurface,
                                    fontSize: 34,
                                    height: 1.12,
                                    letterSpacing: -1,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Text(
                              'Your sessions, goals and expenses stay with your '
                              'account — so a new phone or a reinstall does not '
                              'cost you your records.',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    height: 1.5,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 34),
                          GlassSurface(
                            padding: const EdgeInsets.all(22),
                            radius: 20,
                            child: _step == _Step.email
                                ? _emailStep(colors)
                                : _codeStep(colors),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emailStep(ColorScheme colors) => Form(
    key: _emailFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontSize: 20, letterSpacing: -.35),
        ),
        const SizedBox(height: 6),
        Text(
          'We will email you a 6-digit code. No password to remember.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const ValueKey('sign-in-email-field'),
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'you@example.com',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
          validator: _validateEmail,
          onFieldSubmitted: (_) => _sendCode(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorText(message: _error!),
        ],
        const SizedBox(height: 14),
        FilledButton(
          key: const ValueKey('send-code-button'),
          onPressed: _busy ? null : _sendCode,
          child: Text(_busy ? 'Sending…' : 'Email me a code'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Only your earnings data. We never ask for bank details.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _codeStep(ColorScheme colors) => Form(
    key: _codeFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter your code',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontSize: 20, letterSpacing: -.35),
        ),
        const SizedBox(height: 6),
        Text(
          'Sent to ${_email.text.trim()}.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const ValueKey('sign-in-code-field'),
          controller: _code,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
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
          onFieldSubmitted: (_) => _verifyCode(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorText(message: _error!),
        ],
        const SizedBox(height: 14),
        FilledButton(
          key: const ValueKey('verify-code-button'),
          onPressed: _busy ? null : _verifyCode,
          child: Text(_busy ? 'Checking…' : 'Sign in'),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: const ValueKey('change-email-button'),
          onPressed: _busy
              ? null
              : () => setState(() {
                  _step = _Step.email;
                  _code.clear();
                  _error = null;
                }),
          child: const Text('Use a different email'),
        ),
      ],
    ),
  );

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

  Future<void> _sendCode() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.gateway.sendCode(_email.text.trim());
      if (!mounted) return;
      setState(() => _step = _Step.code);
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (!_codeFormKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The signed-in state is observed through the gateway's stream, so
      // nothing here has to navigate — the app swaps the screen out.
      await widget.gateway.verifyCode(
        email: _email.text.trim(),
        code: _code.text.trim(),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        const SizedBox(width: 8),
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

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        const BrandMark(size: 38),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Driver Wealth',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: -.25,
              ),
            ),
            Text(
              'Profit intelligence for drivers',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}
