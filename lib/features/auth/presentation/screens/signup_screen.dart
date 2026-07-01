import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../providers/auth_provider.dart';
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
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
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
      // Router redirect khud bhi /setup pe le jayega (profile incomplete hone ki wajah se),
      // lekin explicit navigation se UX fast lagta hai
      context.go('/setup');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
        ),
      ),
    );
  }
}
