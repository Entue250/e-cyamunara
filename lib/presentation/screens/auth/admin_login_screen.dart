// lib/presentation/screens/auth/admin_login_screen.dart
//
// ─── SCREEN 11: REGION ADMIN LOGIN ────────────────────────────────────────────
// Shows: Dark blue gradient top with shield icon, "E-CYAMUNARA",
//        "POLICE REGION ADMIN PORTAL" subtitle, Admin Login heading,
//        "Authorized Personnel Only" badge, Phone + Password fields,
//        LOGIN AS ADMIN button, security warning footer.
//
// Connected to: loginUseCaseProvider (isAdmin: true)
// Navigation: On success (region_admin) → admin_dashboard_screen.dart
//             On success (super_admin)   → super_dashboard_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/utils/validators.dart';
import '../../app_router.dart';

class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleAdminLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final useCase = ref.read(loginUseCaseProvider);
    final (role, failure) = await useCase(
      phoneNumber: AppValidators.normalizePhone(_phoneController.text.trim()),
      password: _passwordController.text,
      isAdmin: true, // Uses loginAdmin method in auth_repository
    );

    setState(() => _isLoading = false);
    if (!mounted) return;

    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Route based on role
    if (role == 'super_admin') {
      context.go(AppRoutes.superDashboard);
    } else if (role == 'region_admin') {
      context.go(AppRoutes.adminDashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Dark blue gradient top section ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, bottom: 40),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF001040), AppColors.primaryBlue],
              ),
            ),
            child: Column(
              children: [
                // RNP logo
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: AppColors.gold, width: 3),
                  ),
                  child: ClipOval(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(
                        'assets/images/RNP_logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'E-CYAMUNARA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Builder(
                  builder: (ctx) => Text(
                    ctx.l10n.adminPortal,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── White bottom card ───────────────────────────────────────────────
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.adminLogin,
                        style: AppTextStyles.displayMedium,
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          const Icon(
                            Icons.verified_user,
                            size: 16,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            context.l10n.authorizedOnly,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      Text(context.l10n.phoneNumber, style: AppTextStyles.label),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '+250 XXX XXX XXX',
                          prefixIcon: Icon(
                            Icons.phone_outlined,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        validator: AppValidators.phone(context.l10n),
                      ),

                      const SizedBox(height: 20),

                      Text(context.l10n.password, style: AppTextStyles.label),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          prefixIcon: const Icon(
                            Icons.lock_outline,
                            color: AppColors.textSecondary,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? context.l10n.required : null,
                      ),

                      const SizedBox(height: 28),

                      // LOGIN AS ADMIN button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleAdminLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      context.l10n.loginAsAdmin,
                                      style: AppTextStyles.button,
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.arrow_forward, size: 18),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 16),

                      Text(
                        context.l10n.adminSecurityNote,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 20),

                      Center(
                        child: GestureDetector(
                          onTap: () => context.go(AppRoutes.login),
                          child: Text(
                            context.l10n.backToClientLogin,
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
