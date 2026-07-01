import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_status_message.dart';
import '../widgets/auth_text_field.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_clearAuthError);
    _emailController.addListener(_clearAuthError);
    _phoneController.addListener(_clearAuthError);
    _passwordController.addListener(_clearAuthError);
    _confirmPasswordController.addListener(_clearAuthError);
    Future.microtask(() {
      ref.read(authControllerProvider.notifier).clearStatus();
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_clearAuthError);
    _emailController.removeListener(_clearAuthError);
    _phoneController.removeListener(_clearAuthError);
    _passwordController.removeListener(_clearAuthError);
    _confirmPasswordController.removeListener(_clearAuthError);
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _clearAuthError() {
    if (ref.read(authControllerProvider).hasError) {
      ref.read(authControllerProvider.notifier).clearStatus();
    }
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref
        .read(authControllerProvider.notifier)
        .signup(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
        );

    if (success && mounted) {
      context.go('/setup');

      // Email verification is temporarily disabled during development.
      // Re-enable this when Supabase email confirmation is turned back on.
      // final session = Supabase.instance.client.auth.currentSession;
      // if (session != null) {
      //   context.go('/setup');
      //   return;
      // }
      //
      // final email = Uri.encodeComponent(_emailController.text.trim());
      // context.go('/verify-email?email=$email');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;
    final error = authState.hasError ? authState.error : null;

    return AuthLayout(
      maxWidth: 520,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Back Button ──
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.textPrimary,
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
            const SizedBox(height: 8),

            Text(
              AppStrings.signupTitle,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.signupSubtitle,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            if (error != null) AuthStatusMessage(error: error),

            // ── Full Name ──
            AuthTextField(
              controller: _nameController,
              label: AppStrings.fieldFullName,
              hint: AppStrings.hintFullName,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return AppStrings.errorNameRequired;
                }
                return null;
              },
            ),

            // ── Email ──
            AuthTextField(
              controller: _emailController,
              label: AppStrings.fieldEmail,
              hint: AppStrings.hintEmail,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return AppStrings.errorEmailRequired;
                }
                if (!value.contains('@')) {
                  return AppStrings.errorEmailInvalid;
                }
                return null;
              },
            ),

            // ── Phone ──
            AuthTextField(
              controller: _phoneController,
              label: AppStrings.fieldPhone,
              hint: AppStrings.hintPhone,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.trim().length < 10) {
                  return AppStrings.errorPhoneInvalid;
                }
                return null;
              },
            ),

            // ── Password ──
            AuthTextField(
              controller: _passwordController,
              label: AppStrings.fieldPassword,
              hint: AppStrings.hintPassword,
              isPassword: true,
              validator: (value) {
                if (value == null || value.length < 6) {
                  return AppStrings.errorPasswordTooShort;
                }
                return null;
              },
            ),

            // ── Confirm Password ──
            AuthTextField(
              controller: _confirmPasswordController,
              label: AppStrings.fieldConfirmPassword,
              hint: AppStrings.hintPassword,
              isPassword: true,
              validator: (value) {
                if (value != _passwordController.text) {
                  return AppStrings.errorPasswordMismatch;
                }
                return null;
              },
            ),

            const SizedBox(height: 8),

            // ── Signup Button ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : _handleSignup,
                child:
                    isLoading
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : Text(AppStrings.signupButton),
              ),
            ),
            const SizedBox(height: 32),

            // ── Already have account ──
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text(AppStrings.alreadyHaveAccount),
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Text(
                      AppStrings.loginLink,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
