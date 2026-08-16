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
    return Scaffold(
      appBar: AppBar(
        title: const Text('TelePlayer'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Icon(
                  Icons.play_circle_fill,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Sign in to Telegram',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (auth.error != null) ...[
                  ErrorPanel(error: auth.error!, onAction: () => unawaited(auth.initialize())),
                  const SizedBox(height: 16),
                ],
                if (!settings.hasTelegramConfiguration || step == AuthStepKind.needsConfiguration) ...[
                  FilledButton.icon(
                    onPressed: widget.onOpenSettings,
                    icon: const Icon(Icons.key_outlined),
                    label: const Text('Add Telegram keys'),
                  ),
                ] else if (step == AuthStepKind.unknown) ...[
                  FilledButton.icon(
                    onPressed: auth.isBusy ? null : () => unawaited(auth.initialize()),
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Start sign-in'),
                  ),
                ] else if (step == AuthStepKind.needsCode) ...[
                  TextField(
                    key: const ValueKey<String>('telegram-login-code'),
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Login code',
                      prefixIcon: Icon(Icons.pin_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_submitCode(auth)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: auth.isBusy ? null : () => unawaited(_submitCode(auth)),
                    icon: const Icon(Icons.login),
                    label: const Text('Verify code'),
                  ),
                ] else if (step == AuthStepKind.needsPassword) ...[
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
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_submitPassword(auth)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: auth.isBusy ? null : () => unawaited(_submitPassword(auth)),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Verify password'),
                  ),
                ] else ...[
                  TextField(
                    key: const ValueKey<String>('telegram-phone-number'),
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+15551234567',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_submitPhone(auth)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: auth.isBusy ? null : () => unawaited(_submitPhone(auth)),
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Send code'),
                  ),
                ],
                if (auth.isBusy) ...[
                  const SizedBox(height: 20),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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
