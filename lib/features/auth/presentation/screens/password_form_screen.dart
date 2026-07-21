import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';

class PasswordFormScreen extends ConsumerStatefulWidget {
  final bool isRecovery;

  const PasswordFormScreen.recovery({super.key}) : isRecovery = true;
  const PasswordFormScreen.change({super.key}) : isRecovery = false;

  @override
  ConsumerState<PasswordFormScreen> createState() => _PasswordFormScreenState();
}

class _PasswordFormScreenState extends ConsumerState<PasswordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );

      if (widget.isRecovery) {
        ref.read(passwordRecoveryRefreshProvider).complete();
        await Supabase.instance.client.auth.signOut();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password successfully update ho gaya.')),
      );
      context.go(widget.isRecovery ? '/login' : '/settings');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password update nahi hua: $error')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isRecovery ? 'Reset password' : 'Change password'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          widget.isRecovery
                              ? Icons.lock_reset_rounded
                              : Icons.password_rounded,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.isRecovery
                              ? 'Create a new password'
                              : 'Change your password',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'New password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed:
                                  () => setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                            ),
                          ),
                          validator:
                              (value) =>
                                  (value?.length ?? 0) < 8
                                      ? 'Kam az kam 8 characters required hain'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmation,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'Confirm new password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed:
                                  () => setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                            ),
                          ),
                          validator:
                              (value) =>
                                  value != _password.text
                                      ? 'Passwords match nahi karte'
                                      : null,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child:
                              _saving
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Text('Update password'),
                        ),
                      ],
                    ),
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
