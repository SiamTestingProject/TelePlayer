import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/error_panel.dart';
import '../application/auth_controller.dart';
import '../models/auth_models.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({this.onOpenSettings, super.key});

  final VoidCallback? onOpenSettings;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final auth = scope.authController;
    final settings = scope.settingsController.settings;
    final step = auth.step.kind;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              colors.primaryContainer.withValues(alpha: 0.78),
              colors.secondaryContainer.withValues(alpha: 0.46),
              colors.surface,
            ],
            stops: const <double>[0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'TelePlayer',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Settings',
                          onPressed: widget.onOpenSettings,
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _AuthHero(
                      configured: settings.hasTelegramConfiguration,
                      step: step,
                    ),
                    const SizedBox(height: 18),
                    _AuthPanel(
                      children: <Widget>[
                        Text(
                          'Sign in to Telegram',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _subtitleFor(step, settings.hasTelegramConfiguration),
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 22),
                        if (auth.error != null) ...<Widget>[
                          ErrorPanel(
                            error: auth.error!,
                            onAction: () => unawaited(auth.initialize()),
                          ),
                          const SizedBox(height: 16),
                        ],
                        ..._controlsFor(
                          auth: auth,
                          step: step,
                          configured: settings.hasTelegramConfiguration,
                        ),
                        if (auth.isBusy) ...<Widget>[
                          const SizedBox(height: 20),
                          const LinearProgressIndicator(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _controlsFor({
    required AuthController auth,
    required AuthStepKind step,
    required bool configured,
  }) {
    if (!configured || step == AuthStepKind.needsConfiguration) {
      return <Widget>[
        FilledButton.icon(
          onPressed: widget.onOpenSettings,
          icon: const Icon(Icons.key_outlined),
          label: const Text('Add Telegram keys'),
        ),
      ];
    }
    if (step == AuthStepKind.unknown) {
      return <Widget>[
        FilledButton.icon(
          onPressed: auth.isBusy ? null : () => unawaited(auth.initialize()),
          icon: const Icon(Icons.power_settings_new_rounded),
          label: const Text('Start sign-in'),
        ),
      ];
    }
    if (step == AuthStepKind.needsCode) {
      return <Widget>[
        TextField(
          key: const ValueKey<String>('telegram-login-code'),
          controller: _codeController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Login code',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
          onSubmitted: (_) => unawaited(_submitCode(auth)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: auth.isBusy ? null : () => unawaited(_submitCode(auth)),
          icon: const Icon(Icons.login_rounded),
          label: const Text('Verify code'),
        ),
      ];
    }
    if (step == AuthStepKind.needsPassword) {
      return <Widget>[
        TextField(
          key: const ValueKey<String>('telegram-two-step-password'),
          controller: _passwordController,
          obscureText: true,
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const <String>[AutofillHints.password],
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Two-step password',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
          onSubmitted: (_) => unawaited(_submitPassword(auth)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: auth.isBusy ? null : () => unawaited(_submitPassword(auth)),
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Verify password'),
        ),
      ];
    }
    return <Widget>[
      TextField(
        key: const ValueKey<String>('telegram-phone-number'),
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Phone number',
          hintText: '+15551234567',
          prefixIcon: Icon(Icons.phone_outlined),
        ),
        onSubmitted: (_) => unawaited(_submitPhone(auth)),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: auth.isBusy ? null : () => unawaited(_submitPhone(auth)),
        icon: const Icon(Icons.sms_outlined),
        label: const Text('Send code'),
      ),
    ];
  }

  String _subtitleFor(AuthStepKind step, bool configured) {
    if (!configured || step == AuthStepKind.needsConfiguration) {
      return 'Add your Telegram app keys before connecting your media library.';
    }
    return switch (step) {
      AuthStepKind.unknown => 'Connect your Telegram account to unlock the library.',
      AuthStepKind.needsCode => 'Enter the code Telegram sent to your account.',
      AuthStepKind.needsPassword =>
        'Enter your Telegram two-step verification password.',
      AuthStepKind.ready => 'Your Telegram audio library is ready.',
      AuthStepKind.needsPhone => 'Enter the phone number linked to Telegram.',
      AuthStepKind.expired => 'Your Telegram session expired. Sign in again.',
      AuthStepKind.needsConfiguration =>
        'Add your Telegram app keys before connecting your media library.',
    };
  }

  Future<void> _submitPhone(AuthController auth) async {
    await auth.submitPhone(_phoneController.text.trim());
  }

  Future<void> _submitCode(AuthController auth) {
    return auth.submitCode(_codeController.text.trim());
  }

  Future<void> _submitPassword(AuthController auth) {
    return auth.submitPassword(_passwordController.text);
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({
    required this.configured,
    required this.step,
  });

  final bool configured;
  final AuthStepKind step;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ready = configured && step == AuthStepKind.ready;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(38),
        color: colors.surface.withValues(alpha: 0.52),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  colors.primaryContainer,
                  colors.secondaryContainer,
                  colors.tertiaryContainer,
                ],
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/branding/teleplayer_logo.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  ready ? 'Library Connected' : 'Telegram Media',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  configured ? 'Secure sign-in' : 'Configuration needed',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(34),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
