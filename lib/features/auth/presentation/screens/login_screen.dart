import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_status_message.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/social_login_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_clearAuthError);
    _passwordController.addListener(_clearAuthError);
    Future.microtask(() {
      ref.read(authControllerProvider.notifier).clearStatus();
    });
  }

  @override
  void dispose() {
    _emailController.removeListener(_clearAuthError);
    _passwordController.removeListener(_clearAuthError);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearAuthError() {
    if (ref.read(authControllerProvider).hasError) {
      ref.read(authControllerProvider.notifier).clearStatus();
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref
        .read(authControllerProvider.notifier)
        .login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    if (!success || !mounted) return;

    // check branches count if > 1 then redirect to branch selection else redirect to dashboard
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final profile =
        await Supabase.instance.client
            .from('users')
            .select('tenant_id')
            .eq('id', user.id)
            .maybeSingle();

    final tenantId = profile?['tenant_id'] as String?;
    if (tenantId == null) {
      // user has no tenant/shop yet
      return;
    }

    final branches = await Supabase.instance.client
        .from('branches')
        .select('id, name, address, city')
        .eq('tenant_id', tenantId);

    final actualBranchCount = branches.length;

    debugPrint('Actual branch count: $actualBranchCount');
    if (!mounted) return;

    if (actualBranchCount < 1) {
      context.go('/dashboard'); // router redirect bhi handle karega
    } else {
      context.go('/select-branch');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    final isLoading = authState.isLoading;
    final error = authState.hasError ? authState.error : null;

    return AuthLayout(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome Back',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Apni dukaan ka dashboard access karein',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            if (error != null) AuthStatusMessage(error: error),

            AuthTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Email required hai';
                }
                if (!value.contains('@')) {
                  return 'Valid email likhein';
                }
                return null;
              },
            ),

            AuthTextField(
              controller: _passwordController,
              label: 'Password',
              hint: '••••••••',
              isPassword: true,
              validator: (value) {
                if (value == null || value.length < 6) {
                  return 'Kam az kam 6 characters chahiye';
                }
                return null;
              },
            ),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : _handleLogin,
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
                        : const Text('Login'),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: const [
                Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'OR',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                Expanded(child: Divider(color: AppColors.border)),
              ],
            ),
            const SizedBox(height: 24),

            SocialLoginButton(
              label: 'Continue with Google',
              icon: Icons.g_mobiledata_rounded,
              onPressed:
                  isLoading
                      ? null
                      : () async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .loginWithGoogle();
                      },
            ),
            const SizedBox(height: 32),

            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  const Text("Account nahi hai? "),
                  GestureDetector(
                    onTap: () => context.push('/signup'),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
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
