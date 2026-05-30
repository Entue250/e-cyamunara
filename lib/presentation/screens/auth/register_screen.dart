// lib/presentation/screens/auth/register_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/utils/validators.dart';
import '../../../core/services/encryption_service.dart';
import '../../../data/models/districts_data.dart';
import '../../app_router.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNamesController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPwController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _selectedDistrict;

  @override
  void dispose() {
    _fullNamesController.dispose();
    _nationalIdController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDistrict == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseSelectDistrict),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    await EncryptionService.instance.initialize();
    final encryptedNid = EncryptionService.instance.encrypt(
      _nationalIdController.text.trim().replaceAll(' ', ''),
    );

    final province = getProvinceForDistrict(_selectedDistrict!);
    final region = getRegionForDistrict(_selectedDistrict!);

    final useCase = ref.read(registerClientUseCaseProvider);
    final (user, failure) = await useCase(
      fullNames: _fullNamesController.text.trim(),
      nationalId: encryptedNid,
      phoneNumber: AppValidators.normalizePhone(_phoneController.text.trim()),
      district: _selectedDistrict!,
      province: province,
      region: region,
      password: _passwordController.text,
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

    context.go(AppRoutes.regionSelect);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.login),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'E-CYAMUNARA',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Text(l10n.createAccount, style: AppTextStyles.displayLarge),
              const SizedBox(height: 6),
              Text(l10n.registerSubtitle, style: AppTextStyles.bodyMedium),

              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel(l10n.fullNames),
                        _buildField(
                          controller: _fullNamesController,
                          hint: 'Enter your full legal names',
                          icon: Icons.person_outline,
                          validator: AppValidators.fullName(l10n),
                        ),

                        const SizedBox(height: 16),

                        _buildLabel(l10n.nationalId),
                        _buildField(
                          controller: _nationalIdController,
                          hint: '1 19XX 8 XXXXXXX X XX',
                          icon: Icons.badge_outlined,
                          keyboardType: TextInputType.number,
                          validator: AppValidators.nationalId(l10n),
                        ),

                        const SizedBox(height: 16),

                        _buildLabel(l10n.phoneNumber),
                        _buildField(
                          controller: _phoneController,
                          hint: '+250 7XX XXX XXX',
                          icon: Icons.phone_android_outlined,
                          keyboardType: TextInputType.phone,
                          validator: AppValidators.phone(l10n),
                        ),

                        const SizedBox(height: 16),

                        _buildLabel(l10n.selectDistrict),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceGrey,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: _selectedDistrict,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              prefixIcon: Icon(
                                Icons.location_on_outlined,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            hint: Text(l10n.selectDistrictHint),
                            isExpanded: true,
                            items: kRwandaDistricts
                                .map(
                                  (d) => DropdownMenuItem(
                                    value: d.districtName,
                                    child: Text('${d.districtName} (${d.province})'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _selectedDistrict = v),
                            validator: (v) =>
                                v == null ? l10n.pleaseSelectDistrict : null,
                          ),
                        ),

                        const SizedBox(height: 16),

                        _buildLabel(l10n.password),
                        _buildPasswordField(
                          controller: _passwordController,
                          obscure: _obscurePassword,
                          onToggle: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                          validator: AppValidators.password(l10n),
                        ),

                        const SizedBox(height: 16),

                        _buildLabel(l10n.confirmPassword),
                        _buildPasswordField(
                          controller: _confirmPwController,
                          obscure: _obscureConfirm,
                          onToggle: () =>
                              setState(() => _obscureConfirm = !_obscureConfirm),
                          validator: AppValidators.confirmPassword(
                            l10n,
                            () => _passwordController.text,
                          ),
                        ),

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleRegister,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(l10n.registerButton, style: AppTextStyles.button),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${l10n.alreadyHaveAccount} ', style: AppTextStyles.bodyMedium),
                  GestureDetector(
                    onTap: () => context.go(AppRoutes.login),
                    child: Text(
                      l10n.login,
                      style: const TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Text(
                l10n.officialSystem,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: AppTextStyles.label),
      );

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.textSecondary),
        ),
        validator: validator,
      );

  Widget _buildPasswordField({
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: '••••••••',
          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textSecondary),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: AppColors.textSecondary,
            ),
            onPressed: onToggle,
          ),
        ),
        validator: validator,
      );
}
