// lib/presentation/screens/admin/post_auction_screen.dart
//
// SCREEN 14 — POST NEW AUCTION (redesigned for ML-ready metadata)
// 5 collapsible sections: Basic Info, Technical Specs, Ownership & History,
// Auction Details, Photos.
// Category-dependent fields shown/hidden based on _selectedMainCategory.
// itemName auto-computed from brand + model + year on submit.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../app_router.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/date_notification_helpers.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'admin_shared.dart';
import 'auction_form_data.dart';

class PostAuctionScreen extends ConsumerStatefulWidget {
  const PostAuctionScreen({super.key, this.auction});
  final AuctionModel? auction;

  @override
  ConsumerState<PostAuctionScreen> createState() => _PostAuctionScreenState();
}

class _PostAuctionScreenState extends ConsumerState<PostAuctionScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final _plateCtrl          = TextEditingController();
  final _priceCtrl          = TextEditingController();
  final _descriptionCtrl    = TextEditingController();
  final _modelCtrl          = TextEditingController();
  final _colorCtrl          = TextEditingController();
  final _mileageCtrl        = TextEditingController();
  final _engineSizeCtrl     = TextEditingController();
  final _engineCcCtrl       = TextEditingController();
  final _seatingCtrl        = TextEditingController();
  final _gearCountCtrl      = TextEditingController();

  // Dropdown state
  String  _selectedMainCategory   = 'vehicle';
  String? _selectedSubCategory;
  String? _selectedBrand;
  int?    _selectedYear;
  String? _selectedFuelType;
  String? _selectedTransmission;
  String? _selectedDrivetrain;
  String? _selectedFrameMaterial;
  String? _selectedSuspension;
  String? _selectedBrake;
  String? _selectedOwnershipHistory;
  String? _selectedAccidentHistory;
  String? _selectedInsuranceStatus;
  String  _selectedCondition      = 'Excellent';

  DateTime? _startDate, _endDate;
  List<XFile> _photos = [];
  bool _isLoading = false;

  bool get _isEditMode => widget.auction != null;

  @override
  void initState() {
    super.initState();
    if (widget.auction case final a?) {
      _priceCtrl.text        = a.startingPrice.toStringAsFixed(0);
      _plateCtrl.text        = a.plateNumber;
      _descriptionCtrl.text  = a.description;
      _modelCtrl.text        = a.model ?? '';
      _colorCtrl.text        = a.color ?? '';
      _mileageCtrl.text      = a.mileage?.toString() ?? '';
      _engineSizeCtrl.text   = a.engineSize?.toString() ?? '';
      _engineCcCtrl.text     = a.engineCc?.toString() ?? '';
      _seatingCtrl.text      = a.seatingCapacity?.toString() ?? '';
      _gearCountCtrl.text    = a.gearCount?.toString() ?? '';

      _selectedMainCategory   = a.resolvedMainCategory.isNotEmpty
          ? a.resolvedMainCategory
          : 'vehicle';
      _selectedSubCategory    = a.subCategory;
      _selectedBrand          = a.brand;
      _selectedYear           = a.manufacturingYear;
      _selectedFuelType       = a.fuelType;
      _selectedTransmission   = a.transmission;
      _selectedDrivetrain     = a.drivetrain;
      _selectedFrameMaterial  = a.frameMaterial;
      _selectedSuspension     = a.suspensionType;
      _selectedBrake          = a.brakeType;
      _selectedOwnershipHistory = a.ownershipHistory;
      _selectedAccidentHistory  = a.accidentHistory;
      _selectedInsuranceStatus  = a.insuranceStatus;
      _selectedCondition = a.condition.isNotEmpty ? a.condition : 'Excellent';
      _startDate = a.startDate;
      _endDate   = a.endDate;
    }
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _priceCtrl.dispose();
    _descriptionCtrl.dispose();
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _mileageCtrl.dispose();
    _engineSizeCtrl.dispose();
    _engineCcCtrl.dispose();
    _seatingCtrl.dispose();
    _gearCountCtrl.dispose();
    super.dispose();
  }

  void _onMainCategoryChanged(String newCategory) {
    setState(() {
      _selectedMainCategory   = newCategory;
      _selectedSubCategory    = null;
      _selectedBrand          = null;
      _selectedFuelType       = null;
      _selectedTransmission   = null;
      _selectedDrivetrain     = null;
      _selectedFrameMaterial  = null;
      _selectedSuspension     = null;
      _selectedBrake          = null;
      _engineSizeCtrl.clear();
      _engineCcCtrl.clear();
      _seatingCtrl.clear();
      _gearCountCtrl.clear();
    });
  }

  String _computeItemName() {
    final parts = <String>[
      ?_selectedBrand,
      if (_modelCtrl.text.trim().isNotEmpty) _modelCtrl.text.trim(),
      ?_selectedYear?.toString(),
    ];
    if (parts.isEmpty) return widget.auction?.itemName ?? '';
    return parts.join(' ');
  }

  Future<void> _pickPhotos() async {
    final imgs = await ImagePicker().pickMultiImage(limit: 5);
    if (imgs.isNotEmpty) setState(() => _photos = imgs);
  }

  Future<void> _pickDate(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(Duration(days: isStart ? 0 : 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => isStart ? _startDate = date : _endDate = date);
    }
  }

  Future<void> _submit(bool isDraft) async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.selectDatesError)),
      );
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.endDateAfterStartError),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final admin = ref.read(currentAdminProvider).value;
    if (admin == null) { setState(() => _isLoading = false); return; }

    final price = double.tryParse(
            _priceCtrl.text.trim().replaceAll(',', '')) ?? 0;
    final computedName = _computeItemName();

    if (_isEditMode) {
      final updated = widget.auction!.copyWith(
        itemName:         computedName.isNotEmpty ? computedName : null,
        category:         _selectedMainCategory,
        mainCategory:     _selectedMainCategory,
        subCategory:      _selectedSubCategory,
        brand:            _selectedBrand,
        model:            _modelCtrl.text.trim().isNotEmpty
                              ? _modelCtrl.text.trim() : null,
        manufacturingYear: _selectedYear,
        color:            _colorCtrl.text.trim().isNotEmpty
                              ? _colorCtrl.text.trim() : null,
        plateNumber:      _plateCtrl.text.trim(),
        condition:        _selectedCondition,
        mileage:          int.tryParse(_mileageCtrl.text.trim()),
        fuelType:         _selectedFuelType,
        transmission:     _selectedTransmission,
        engineSize:       double.tryParse(_engineSizeCtrl.text.trim()),
        engineCc:         int.tryParse(_engineCcCtrl.text.trim()),
        drivetrain:       _selectedDrivetrain,
        seatingCapacity:  int.tryParse(_seatingCtrl.text.trim()),
        frameMaterial:    _selectedFrameMaterial,
        gearCount:        int.tryParse(_gearCountCtrl.text.trim()),
        suspensionType:   _selectedSuspension,
        brakeType:        _selectedBrake,
        ownershipHistory: _selectedOwnershipHistory,
        accidentHistory:  _selectedAccidentHistory,
        insuranceStatus:  _selectedInsuranceStatus,
        description:      _descriptionCtrl.text.trim(),
        startingPrice:    price,
        startDate:        _startDate!,
        endDate:          _endDate!,
        updatedAt:        DateTime.now(),
      );

      final failure = await ref.read(updateAuctionUseCaseProvider)(updated);
      setState(() => _isLoading = false);
      if (!mounted) return;
      if (failure != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ));
        return;
      }
      ref.invalidate(adminAuctionsProvider(admin.uid));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.auctionUpdatedSuccess),
        backgroundColor: AppColors.success,
      ));
      context.go(AppRoutes.manageAuctions);
      return;
    }

    // Create mode
    final auction = AuctionModel(
      auctionId:        '',
      itemName:         computedName,
      category:         _selectedMainCategory,
      mainCategory:     _selectedMainCategory,
      subCategory:      _selectedSubCategory,
      brand:            _selectedBrand,
      model:            _modelCtrl.text.trim().isNotEmpty
                            ? _modelCtrl.text.trim() : null,
      manufacturingYear: _selectedYear,
      color:            _colorCtrl.text.trim().isNotEmpty
                            ? _colorCtrl.text.trim() : null,
      plateNumber:      _plateCtrl.text.trim(),
      condition:        _selectedCondition,
      mileage:          int.tryParse(_mileageCtrl.text.trim()),
      fuelType:         _selectedFuelType,
      transmission:     _selectedTransmission,
      engineSize:       double.tryParse(_engineSizeCtrl.text.trim()),
      engineCc:         int.tryParse(_engineCcCtrl.text.trim()),
      drivetrain:       _selectedDrivetrain,
      seatingCapacity:  int.tryParse(_seatingCtrl.text.trim()),
      frameMaterial:    _selectedFrameMaterial,
      gearCount:        int.tryParse(_gearCountCtrl.text.trim()),
      suspensionType:   _selectedSuspension,
      brakeType:        _selectedBrake,
      ownershipHistory: _selectedOwnershipHistory,
      accidentHistory:  _selectedAccidentHistory,
      insuranceStatus:  _selectedInsuranceStatus,
      description:      _descriptionCtrl.text.trim(),
      photoUrls:        [],
      startingPrice:    price,
      currentHighestBid: price,
      totalBids:        0,
      region:           admin.region,
      postedByAdminUid: admin.uid,
      postedByAdminName: admin.fullNames,
      auctionStatus:    isDraft ? 'draft' : 'active',
      startDate:        _startDate!,
      endDate:          _endDate!,
      createdAt:        DateTime.now(),
      updatedAt:        DateTime.now(),
    );

    final files   = _photos.map((x) => File(x.path)).toList();
    final (_, failure) = await ref.read(postAuctionUseCaseProvider)(auction, files);
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failure.message),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    ref.invalidate(adminAuctionsProvider(admin.uid));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isDraft
          ? context.l10n.auctionSavedDraft
          : context.l10n.auctionPostedSuccess),
      backgroundColor: AppColors.success,
    ));
    context.go(AppRoutes.manageAuctions);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(currentAdminProvider).value;
    final l10n  = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditMode ? l10n.editAuction : l10n.postNewAuction),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.sovereignLedger, style: AppTextStyles.labelGold),
              Text(l10n.registerAssets,  style: AppTextStyles.displayMedium),
              Text(l10n.formalDocumentation, style: AppTextStyles.bodyMedium),
              const SizedBox(height: 20),

              _buildSection1(context, l10n),
              const SizedBox(height: 6),
              _buildSection2(context, l10n),
              const SizedBox(height: 6),
              _buildSection3(context, l10n),
              const SizedBox(height: 6),
              _buildSection4(context, l10n, admin),
              const SizedBox(height: 6),
              _buildSection5(context, l10n),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _submit(false),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isEditMode
                              ? l10n.saveChangesButton
                              : l10n.postAuction,
                          style: AppTextStyles.button,
                        ),
                ),
              ),
              if (!_isEditMode) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: _isLoading ? null : () => _submit(true),
                    child: Text(
                      l10n.saveAsDraft,
                      style: const TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AdminBottomNav(currentIndex: 1),
    );
  }

  // ── Section 1: Basic Information ─────────────────────────────────────────────
  Widget _buildSection1(BuildContext context, AppLocalizations l10n) {
    return _SectionTile(
      icon: Icons.info_outline,
      title: l10n.basicInformation,
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main category chips
          FormLabel(l10n.mainCategoryLabel),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AuctionFormData.mainCategories.map((cat) {
              final isSel = _selectedMainCategory == cat;
              return GestureDetector(
                onTap: () => _onMainCategoryChanged(cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSel
                        ? AppColors.primaryBlue
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: isSel
                          ? AppColors.primaryBlue
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AuctionFormData.categoryIcon(cat),
                        size: 14,
                        color: isSel
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AuctionFormData.mainCategoryLabel(context, cat),
                        style: TextStyle(
                          color: isSel
                              ? Colors.white
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Sub-category
          _buildDropdown<String>(
            label: l10n.subCategoryLabel,
            value: _selectedSubCategory,
            hint: l10n.selectSubCategory,
            items: AuctionFormData.subcategoryMap[_selectedMainCategory] ?? [],
            labelBuilder: (v) => v,
            onChanged: (v) => setState(() => _selectedSubCategory = v),
            validator: (v) => AuctionValidators.validateRequiredDropdown(
                v, l10n.validatorSubCategoryRequired),
          ),

          const SizedBox(height: 12),

          // Brand
          _buildDropdown<String>(
            label: l10n.brandLabel,
            value: _selectedBrand,
            hint: l10n.selectBrand,
            items: AuctionFormData.brandMap[_selectedMainCategory] ?? [],
            labelBuilder: (v) => v,
            onChanged: (v) => setState(() => _selectedBrand = v),
            validator: (v) => AuctionValidators.validateRequiredDropdown(
                v, l10n.validatorBrandRequired),
          ),

          const SizedBox(height: 12),

          // Model
          _buildTextField(
            label: l10n.modelField,
            controller: _modelCtrl,
            hint: 'e.g. RAV4 / R15 / Talon 3',
            validator: (v) => AuctionValidators.validateRequired(
                v, l10n.validatorModelRequired),
          ),

          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDropdown<int>(
                  label: l10n.manufacturingYearLabel,
                  value: _selectedYear,
                  hint: 'YYYY',
                  items: AuctionFormData.years,
                  labelBuilder: (v) => v.toString(),
                  onChanged: (v) => setState(() => _selectedYear = v),
                  validator: (v) =>
                      AuctionValidators.validateYear(v, l10n),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  label: l10n.colorField,
                  controller: _colorCtrl,
                  hint: 'e.g. White',
                  validator: (v) => AuctionValidators.validateRequired(
                      v, l10n.validatorColorRequired),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Plate number — hidden for bicycle
          if (_selectedMainCategory != 'bicycle')
            _buildTextField(
              label: l10n.plateNumberField,
              controller: _plateCtrl,
              hint: 'RAD 000 A',
              validator: (v) => AuctionValidators.validateRequired(
                  v, l10n.required),
            ),

          if (_selectedMainCategory == 'bicycle')
            Builder(builder: (_) {
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _plateCtrl.clear());
              return const SizedBox.shrink();
            }),
        ],
      ),
    );
  }

  // ── Section 2: Technical Specifications ──────────────────────────────────────
  Widget _buildSection2(BuildContext context, AppLocalizations l10n) {
    return _SectionTile(
      icon: Icons.settings_outlined,
      title: l10n.technicalSpecs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Condition — all categories
          _buildDropdown<String>(
            label: l10n.conditionField,
            value: _selectedCondition,
            hint: l10n.selectCondition,
            items: AuctionFormData.conditions,
            labelBuilder: (v) =>
                AuctionFormData.conditionLabel(context, v),
            onChanged: (v) =>
                setState(() => _selectedCondition = v ?? 'Excellent'),
            validator: (_) => null,
          ),

          const SizedBox(height: 12),

          // Mileage — vehicle + motorcycle
          if (_selectedMainCategory != 'bicycle') ...[
            _buildTextField(
              label: l10n.mileageField,
              controller: _mileageCtrl,
              hint: '45000',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => AuctionValidators.validateMileage(
                  v, _selectedMainCategory, l10n),
            ),
            const SizedBox(height: 12),
          ],

          // Vehicle-specific fields
          if (_selectedMainCategory == 'vehicle') ...[
            _buildDropdown<String>(
              label: l10n.fuelTypeField,
              value: _selectedFuelType,
              hint: l10n.selectFuelType,
              items: AuctionFormData.fuelTypes,
              labelBuilder: (v) =>
                  AuctionFormData.fuelTypeLabel(context, v),
              onChanged: (v) =>
                  setState(() => _selectedFuelType = v),
              validator: (v) => AuctionValidators.validateFuelType(
                  v, _selectedMainCategory, l10n),
            ),
            const SizedBox(height: 12),
            _buildDropdown<String>(
              label: l10n.transmissionField,
              value: _selectedTransmission,
              hint: l10n.selectTransmission,
              items: AuctionFormData.transmissions,
              labelBuilder: (v) =>
                  AuctionFormData.transmissionLabel(context, v),
              onChanged: (v) =>
                  setState(() => _selectedTransmission = v),
              validator: (v) => AuctionValidators.validateTransmission(
                  v, _selectedMainCategory, l10n),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildTextField(
                    label: l10n.engineSizeField,
                    controller: _engineSizeCtrl,
                    hint: '2.5',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    validator: (v) =>
                        AuctionValidators.validateEngineSize(
                            v, _selectedMainCategory, l10n),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDropdown<String>(
                    label: l10n.drivetrainField,
                    value: _selectedDrivetrain,
                    hint: l10n.selectDrivetrain,
                    items: AuctionFormData.drivetrains,
                    labelBuilder: (v) => v,
                    onChanged: (v) =>
                        setState(() => _selectedDrivetrain = v),
                    validator: (_) => null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTextField(
              label: l10n.seatingCapacityField,
              controller: _seatingCtrl,
              hint: '5',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (_) => null,
            ),
          ],

          // Motorcycle-specific fields
          if (_selectedMainCategory == 'motorcycle') ...[
            _buildDropdown<String>(
              label: l10n.fuelTypeField,
              value: _selectedFuelType,
              hint: l10n.selectFuelType,
              items: AuctionFormData.fuelTypes,
              labelBuilder: (v) =>
                  AuctionFormData.fuelTypeLabel(context, v),
              onChanged: (v) =>
                  setState(() => _selectedFuelType = v),
              validator: (v) => AuctionValidators.validateFuelType(
                  v, _selectedMainCategory, l10n),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              label: l10n.engineCcField,
              controller: _engineCcCtrl,
              hint: '155',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => AuctionValidators.validateEngineCc(
                  v, _selectedMainCategory, l10n),
            ),
          ],

          // Bicycle-specific fields
          if (_selectedMainCategory == 'bicycle') ...[
            _buildDropdown<String>(
              label: l10n.frameMaterialField,
              value: _selectedFrameMaterial,
              hint: l10n.selectFrameMaterial,
              items: AuctionFormData.frameMaterials,
              labelBuilder: (v) => v,
              onChanged: (v) =>
                  setState(() => _selectedFrameMaterial = v),
              validator: (_) => null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildTextField(
                    label: l10n.gearCountField,
                    controller: _gearCountCtrl,
                    hint: '21',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    validator: (v) =>
                        AuctionValidators.validateGearCount(
                            v, _selectedMainCategory, l10n),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDropdown<String>(
                    label: l10n.suspensionTypeField,
                    value: _selectedSuspension,
                    hint: l10n.selectSuspension,
                    items: AuctionFormData.suspensions,
                    labelBuilder: (v) => v,
                    onChanged: (v) =>
                        setState(() => _selectedSuspension = v),
                    validator: (_) => null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDropdown<String>(
              label: l10n.brakeTypeField,
              value: _selectedBrake,
              hint: l10n.selectBrakeType,
              items: AuctionFormData.brakeTypes,
              labelBuilder: (v) => v,
              onChanged: (v) => setState(() => _selectedBrake = v),
              validator: (_) => null,
            ),
          ],
        ],
      ),
    );
  }

  // ── Section 3: Ownership & History ───────────────────────────────────────────
  Widget _buildSection3(BuildContext context, AppLocalizations l10n) {
    return _SectionTile(
      icon: Icons.history_outlined,
      title: l10n.ownershipSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDropdown<String>(
            label: l10n.ownershipHistoryField,
            value: _selectedOwnershipHistory,
            hint: l10n.selectOwnershipHistory,
            items: AuctionFormData.ownershipOptions,
            labelBuilder: (v) =>
                AuctionFormData.ownershipLabel(context, v),
            onChanged: (v) =>
                setState(() => _selectedOwnershipHistory = v),
            validator: (_) => null,
          ),
          const SizedBox(height: 12),
          _buildDropdown<String>(
            label: l10n.accidentHistoryField,
            value: _selectedAccidentHistory,
            hint: l10n.selectAccidentHistory,
            items: AuctionFormData.accidentOptions,
            labelBuilder: (v) =>
                AuctionFormData.accidentLabel(context, v),
            onChanged: (v) =>
                setState(() => _selectedAccidentHistory = v),
            validator: (_) => null,
          ),
          const SizedBox(height: 12),
          _buildDropdown<String>(
            label: l10n.insuranceStatusField,
            value: _selectedInsuranceStatus,
            hint: l10n.selectInsuranceStatus,
            items: AuctionFormData.insuranceOptions,
            labelBuilder: (v) =>
                AuctionFormData.insuranceLabel(context, v),
            onChanged: (v) =>
                setState(() => _selectedInsuranceStatus = v),
            validator: (_) => null,
          ),
        ],
      ),
    );
  }

  // ── Section 4: Auction Details ────────────────────────────────────────────────
  Widget _buildSection4(
      BuildContext context, AppLocalizations l10n, dynamic admin) {
    return _SectionTile(
      icon: Icons.gavel_outlined,
      title: l10n.auctionDetailsSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormLabel(l10n.startingPrice),
          TextFormField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '5,000,000',
              suffixText: 'RWF',
            ),
            validator: (v) =>
                AuctionValidators.validateRequired(v, l10n.required),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(child: _buildDatePicker(
                  context, l10n.startDate, _startDate, () => _pickDate(true))),
              const SizedBox(width: 12),
              Expanded(child: _buildDatePicker(
                  context, l10n.endDate, _endDate, () => _pickDate(false))),
            ],
          ),

          const SizedBox(height: 16),

          FormLabel(l10n.storageRegion),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceGrey,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Text(
                  '${admin?.region ?? ''} Region',
                  style: AppTextStyles.bodyLarge,
                ),
                const Spacer(),
                const Icon(Icons.lock_outline,
                    size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),

          const SizedBox(height: 16),

          FormLabel(l10n.descriptionField),
          TextFormField(
            controller: _descriptionCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: l10n.formalDocumentation,
            ),
            validator: AppValidators.validateDescription,
          ),
        ],
      ),
    );
  }

  // ── Section 5: Photos ──────────────────────────────────────────────────────
  Widget _buildSection5(BuildContext context, AppLocalizations l10n) {
    return _SectionTile(
      icon: Icons.photo_camera_outlined,
      title: l10n.itemPhotos,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (!_isEditMode)
                  GestureDetector(
                    onTap: _pickPhotos,
                    child: Container(
                      width: 80,
                      height: 80,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primaryBlue),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.upload_outlined,
                              color: AppColors.primaryBlue),
                          Text(
                            l10n.upload,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isEditMode)
                  ...widget.auction!.photoUrls.map((url) => Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          image: DecorationImage(
                            image: NetworkImage(url),
                            fit: BoxFit.cover,
                          ),
                        ),
                      )),
                if (!_isEditMode)
                  ..._photos.map((f) => Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          image: DecorationImage(
                            image: FileImage(File(f.path)),
                            fit: BoxFit.cover,
                          ),
                        ),
                      )),
              ],
            ),
          ),
          if (_isEditMode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.photosCannotChange,
                  style: AppTextStyles.bodySmall),
            ),
          if (!_isEditMode && _photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.photosSelected(_photos.length),
                  style: AppTextStyles.bodySmall),
            ),
        ],
      ),
    );
  }

  // ── Shared field builders ────────────────────────────────────────────────────

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required String hint,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
    FormFieldValidator<T?>? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(label),
        DropdownButtonFormField<T>(
          initialValue: value,
          decoration: InputDecoration(hintText: hint),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(
                      labelBuilder(item),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    FormFieldValidator<String>? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(label),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(hintText: hint),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildDatePicker(
    BuildContext context,
    String label,
    DateTime? date,
    VoidCallback onTap,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(label),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceGrey,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              date != null
                  ? DateHelper.formatDate(date)
                  : 'mm/dd/yyyy',
              style: TextStyle(
                color: date != null
                    ? AppColors.textPrimary
                    : AppColors.textHint,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionTile — styled ExpansionTile matching RNP brand
// ─────────────────────────────────────────────────────────────────────────────
class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
          ),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            leading: Icon(icon, size: 18, color: AppColors.primaryBlue),
            title: Text(title, style: AppTextStyles.labelGold),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [child],
          ),
        ),
      );
}
