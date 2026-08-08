import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_status_message.dart';

class PasswordFormScreen extends ConsumerStatefulWidget {
  final bool isRecovery;

  const PasswordFormScreen.recovery({super.key}) : isRecovery = true;
  const PasswordFormScreen.change({super.key}) : isRecovery = false;

  @override
  ConsumerState<PasswordFormScreen> createState() => _PasswordFormScreenState();
}

class _PasswordFormScreenState extends ConsumerState<PasswordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  bool _saving = false;
  bool _showCurrentPassword = false;
  bool _showPassword = false;
  bool _showConfirmation = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _currentPassword.addListener(_clearError);
    _password.addListener(_onPasswordChanged);
    _confirmation.addListener(_clearError);
  }

  @override
  void dispose() {
    _currentPassword.removeListener(_clearError);
    _password.removeListener(_onPasswordChanged);
    _confirmation.removeListener(_clearError);
    _currentPassword.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  void _onPasswordChanged() {
    _clearError();
    setState(() {});
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final auth = Supabase.instance.client.auth;
    try {
      if (!widget.isRecovery) {
        final email = auth.currentUser?.email;
        if (email == null || email.isEmpty) {
          throw const AuthException(
            'Your login session is unavailable. Please sign in again.',
          );
        }

        // Supabase updateUser only requires an active session. Re-authenticate
        // first so a person holding an unlocked device cannot change the login.
        await auth.signInWithPassword(
          email: email,
          password: _currentPassword.text,
        );
      }

      await auth.updateUser(UserAttributes(password: _password.text));

      if (widget.isRecovery) {
        ref.read(passwordRecoveryRefreshProvider).complete();
        await auth.signOut();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Password successfully update ho gaya.'),
            backgroundColor: AppColors.success,
          ),
        );
      context.go(widget.isRecovery ? '/login' : '/settings');
    } catch (error) {
      if (!mounted) return;
      final message = error is AuthException ? error.message.toLowerCase() : '';
      setState(() {
        _error =
            !widget.isRecovery &&
                    (message.contains('invalid login credentials') ||
                        message.contains('invalid credentials'))
                ? const AuthException('Current password sahi nahi hai.')
                : error;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _newPasswordValidator(String? value) {
    final password = value ?? '';
    if (password.length < 8) return 'Kam az kam 8 characters required hain';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Kam az kam 1 letter aur 1 number add karein';
    }
    if (!widget.isRecovery && password == _currentPassword.text) {
      return 'Naya password current password se different hona chahiye';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isRecovery ? 'Reset password' : 'Change password';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _saving ? null : () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(title),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          widget.isRecovery
                              ? Icons.lock_reset_rounded
                              : Icons.shield_outlined,
                          color: AppColors.primary,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.isRecovery
                            ? 'Apne account ke liye ek naya secure password banayein.'
                            : 'Pehle current password verify karein, phir naya password set karein.',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_error != null) AuthStatusMessage(error: _error!),
                      if (!widget.isRecovery) ...[
                        _PasswordField(
                          controller: _currentPassword,
                          label: 'Current password',
                          hint: 'Apna current password enter karein',
                          visible: _showCurrentPassword,
                          autofillHint: AutofillHints.password,
                          onToggleVisibility:
                              () => setState(
                                () =>
                                    _showCurrentPassword =
                                        !_showCurrentPassword,
                              ),
                          validator:
                              (value) =>
                                  (value?.isEmpty ?? true)
                                      ? 'Current password required hai'
                                      : null,
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: AppColors.divider),
                        const SizedBox(height: 16),
                      ],
                      _PasswordField(
                        controller: _password,
                        label: 'New password',
                        hint: 'Kam az kam 8 characters',
                        visible: _showPassword,
                        onToggleVisibility:
                            () =>
                                setState(() => _showPassword = !_showPassword),
                        validator: _newPasswordValidator,
                      ),
                      const SizedBox(height: 10),
                      _PasswordRequirements(password: _password.text),
                      const SizedBox(height: 16),
                      _PasswordField(
                        controller: _confirmation,
                        label: 'Confirm new password',
                        hint: 'Naya password dobara enter karein',
                        visible: _showConfirmation,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saving ? null : _save(),
                        onToggleVisibility:
                            () => setState(
                              () => _showConfirmation = !_showConfirmation,
                            ),
                        validator: (value) {
                          if (value?.isEmpty ?? true) {
                            return 'Password confirmation required hai';
                          }
                          return value != _password.text
                              ? 'Passwords match nahi karte'
                              : null;
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon:
                              _saving
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(Icons.lock_outline_rounded),
                          label: Text(
                            _saving ? 'Updating...' : 'Update password',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool visible;
  final String autofillHint;
  final VoidCallback onToggleVisibility;
  final String? Function(String?) validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.visible,
    required this.onToggleVisibility,
    required this.validator,
    this.autofillHint = AutofillHints.newPassword,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    obscureText: !visible,
    enableSuggestions: false,
    autocorrect: false,
    autofillHints: [autofillHint],
    textInputAction: textInputAction,
    onFieldSubmitted: onSubmitted,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        tooltip: visible ? 'Hide password' : 'Show password',
        onPressed: onToggleVisibility,
        icon: Icon(
          visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        ),
      ),
    ),
    validator: validator,
  );
}

class _PasswordRequirements extends StatelessWidget {
  final String password;

  const _PasswordRequirements({required this.password});

  @override
  Widget build(BuildContext context) {
    final hasLength = password.length >= 8;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _Requirement(label: '8+ characters', met: hasLength),
        _Requirement(label: '1 letter', met: hasLetter),
        _Requirement(label: '1 number', met: hasNumber),
      ],
    );
  }
}

class _Requirement extends StatelessWidget {
  final String label;
  final bool met;

  const _Requirement({required this.label, required this.met});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        met ? Icons.check_circle_rounded : Icons.circle_outlined,
        size: 15,
        color: met ? AppColors.success : AppColors.textHint,
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(
          color: met ? AppColors.success : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
