import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/password_recovery.dart';
import '../widgets/auth_layout.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.addListener(_clearError);
  }

  @override
  void dispose() {
    _email.removeListener(_clearError);
    _email.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _email.text.trim().toLowerCase(),
        redirectTo: passwordRecoveryRedirectUrl(),
      );
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = passwordRecoveryErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _changeEmail() {
    setState(() {
      _sent = false;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  color: AppColors.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _sent ? 'Check your email' : 'Forgot password?',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _sent
                    ? 'Hum ne ${maskRecoveryEmail(_email.text)} par password reset link bhej diya hai.'
                    : 'Apna registered email enter karein. Hum aap ko secure reset link bhejein ge.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              if (_sent) ...[
                const _RecoveryStep(
                  icon: Icons.mail_outline_rounded,
                  text: 'Inbox aur spam folder check karein.',
                ),
                const SizedBox(height: 12),
                const _RecoveryStep(
                  icon: Icons.link_rounded,
                  text: 'Email mein maujood reset link open karein.',
                ),
                const SizedBox(height: 12),
                const _RecoveryStep(
                  icon: Icons.lock_reset_rounded,
                  text: 'Naya password set karke dobara login karein.',
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _sending ? null : _send,
                  icon:
                      _sending
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.refresh_rounded),
                  label: Text(_sending ? 'Sending...' : 'Resend reset link'),
                ),
                TextButton(
                  onPressed: _sending ? null : _changeEmail,
                  child: const Text('Use a different email'),
                ),
              ] else ...[
                TextFormField(
                  controller: _email,
                  autofocus: true,
                  enabled: !_sending,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  onFieldSubmitted: (_) => _sending ? null : _send(),
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (!RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(email)) {
                      return 'Valid email address enter karein';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    icon:
                        _sending
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.send_rounded),
                    label: Text(_sending ? 'Sending...' : 'Send reset link'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _sending ? null : () => context.go('/login'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoveryStep extends StatelessWidget {
  final IconData icon;
  final String text;

  const _RecoveryStep({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 21, color: AppColors.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    ],
  );
}
