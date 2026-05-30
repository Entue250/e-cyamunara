// lib/presentation/screens/admin/post_auction_screen.dart
//
// SCREEN 14 — POST NEW AUCTION
// Shows: "SOVEREIGN LEDGER / Register Assets" heading, Item Information
//        (name, category chips, plate number, condition), Item Photos
//        (upload + preview grid), Auction Details (starting price, start
//        date, end date, region, description), POST AUCTION + SAVE AS DRAFT.
//
// Providers: postAuctionUseCaseProvider, currentAdminProvider

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../app_router.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/date_notification_helpers.dart';
import '../../../core/utils/validators.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'admin_shared.dart';

class PostAuctionScreen extends ConsumerStatefulWidget {
  const PostAuctionScreen({super.key, this.auction});

  /// Non-null in edit mode; null when creating a new auction.
  final AuctionModel? auction;

  @override
  ConsumerState<PostAuctionScreen> createState() => _PostAuctionScreenState();
}

class _PostAuctionScreenState extends ConsumerState<PostAuctionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _itemNameCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  String _selectedCategory = 'car';
  String _selectedCondition = 'excellent';
  DateTime? _startDate, _endDate;
  List<XFile> _photos = [];
  bool _isLoading = false;

  static const List<String> _conditions = [
    'excellent',
    'good',
    'fair',
    'poor',
  ];

  bool get _isEditMode => widget.auction != null;

  @override
  void initState() {
    super.initState();
    if (widget.auction case final a?) {
      _itemNameCtrl.text = a.itemName;
      _plateCtrl.text = a.plateNumber;
      _priceCtrl.text = a.startingPrice.toStringAsFixed(0);
      _descriptionCtrl.text = a.description;
      _selectedCategory = a.category;
      _selectedCondition = a.condition;
      _startDate = a.startDate;
      _endDate = a.endDate;
    }
  }

  @override
  void dispose() {
    _itemNameCtrl.dispose();
    _plateCtrl.dispose();
    _priceCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final imgs = await picker.pickMultiImage(limit: 5);
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
    if (admin == null) {
      setState(() => _isLoading = false);
      return;
    }

    final price =
        double.tryParse(_priceCtrl.text.trim().replaceAll(',', '')) ?? 0;

    if (_isEditMode) {
      final updated = widget.auction!.copyWith(
        itemName: _itemNameCtrl.text.trim(),
        category: _selectedCategory,
        plateNumber: _plateCtrl.text.trim(),
        condition: _selectedCondition,
        description: _descriptionCtrl.text.trim(),
        startingPrice: price,
        startDate: _startDate!,
        endDate: _endDate!,
        updatedAt: DateTime.now(),
      );
      final failure = await ref.read(updateAuctionUseCaseProvider)(updated);
      setState(() => _isLoading = false);
      if (!mounted) return;
      if (failure != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(failure.message),
              backgroundColor: AppColors.error),
        );
        return;
      }
      ref.invalidate(adminAuctionsProvider(admin.uid));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.auctionUpdatedSuccess),
          backgroundColor: AppColors.success,
        ),
      );
      context.go(AppRoutes.manageAuctions);
      return;
    }

    // Create mode
    final auction = AuctionModel(
      auctionId: '',
      itemName: _itemNameCtrl.text.trim(),
      category: _selectedCategory,
      plateNumber: _plateCtrl.text.trim(),
      condition: _selectedCondition,
      description: _descriptionCtrl.text.trim(),
      photoUrls: [],
      startingPrice: price,
      currentHighestBid: price,
      totalBids: 0,
      region: admin.region,
      postedByAdminUid: admin.uid,
      postedByAdminName: admin.fullNames,
      auctionStatus: isDraft ? 'draft' : 'active',
      startDate: _startDate!,
      endDate: _endDate!,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final useCase = ref.read(postAuctionUseCaseProvider);
    final files = _photos.map((x) => File(x.path)).toList();
    final (_, failure) = await useCase(auction, files);

    setState(() => _isLoading = false);

    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    ref.invalidate(adminAuctionsProvider(admin.uid));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isDraft ? context.l10n.auctionSavedDraft : context.l10n.auctionPostedSuccess),
        backgroundColor: AppColors.success,
      ),
    );
    context.go(AppRoutes.manageAuctions);
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(currentAdminProvider).value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditMode ? context.l10n.editAuction : context.l10n.postNewAuction),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Heading
              Text(context.l10n.sovereignLedger, style: AppTextStyles.labelGold),
              Text(context.l10n.registerAssets, style: AppTextStyles.displayMedium),
              Text(
                context.l10n.formalDocumentation,
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 24),

              // ── ITEM INFORMATION ───────────────────────────────────────
              FormSectionHeader(
                Icons.description_outlined,
                context.l10n.itemInformation,
              ),

              FormLabel(context.l10n.assetName),
              TextFormField(
                controller: _itemNameCtrl,
                decoration: const InputDecoration(
                  hintText: 'e.g. Toyota Hilux 2018',
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Asset name required' : null,
              ),

              const SizedBox(height: 16),
              FormLabel(context.l10n.categoryLabel),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SupabaseConstants.categories.map((cat) {
                  final isSel = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSel
                            ? AppColors.primaryBlue
                            : AppColors.surface,
                        borderRadius:
                            BorderRadius.circular(AppRadius.full),
                        border: Border.all(
                          color: isSel
                              ? AppColors.primaryBlue
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        AppFormatters.titleCase(cat),
                        style: TextStyle(
                          color: isSel
                              ? Colors.white
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FormLabel(context.l10n.plateNumberField),
                        TextFormField(
                          controller: _plateCtrl,
                          decoration: const InputDecoration(
                            hintText: 'RAD 000 A',
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FormLabel(context.l10n.conditionField),
                        DropdownButtonFormField<String>(
                          // ignore: deprecated_member_use
                          value: _selectedCondition,
                          decoration: const InputDecoration(),
                          items: _conditions
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(AppFormatters.titleCase(c)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedCondition = v!),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── ITEM PHOTOS ────────────────────────────────────────────
              FormSectionHeader(
                Icons.photo_camera_outlined,
                context.l10n.itemPhotos,
              ),
              const SizedBox(height: 8),
              if (_isEditMode) ...[
                // Edit mode: show existing photos as read-only strip
                SizedBox(
                  height: 90,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: widget.auction!.photoUrls.isEmpty
                        ? [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceGrey,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: const Icon(
                                Icons.image_not_supported_outlined,
                                color: AppColors.border,
                              ),
                            ),
                          ]
                        : widget.auction!.photoUrls
                            .map(
                              (url) => Container(
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
                              ),
                            )
                            .toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.l10n.photosCannotChange,
                    style: AppTextStyles.bodySmall,
                  ),
                ),
              ] else ...[
                SizedBox(
                  height: 90,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
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
                              const Icon(
                                Icons.upload_outlined,
                                color: AppColors.primaryBlue,
                              ),
                              Text(
                                context.l10n.upload,
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
                      ..._photos.map(
                        (f) => Container(
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
                        ),
                      ),
                    ],
                  ),
                ),
                if (_photos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.l10n.photosSelected(_photos.length),
                      style: AppTextStyles.bodySmall,
                    ),
                  ),
              ],

              const SizedBox(height: 24),

              // ── AUCTION DETAILS ────────────────────────────────────────
              FormSectionHeader(
                Icons.gavel_outlined,
                context.l10n.auctionDetailsSection,
              ),

              FormLabel(context.l10n.startingPrice),
              TextFormField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '5,000,000',
                  suffixText: 'RWF',
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FormLabel(context.l10n.startDate),
                        GestureDetector(
                          onTap: () => _pickDate(true),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceGrey,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                            child: Text(
                              _startDate != null
                                  ? DateHelper.formatDate(_startDate!)
                                  : 'mm/dd/yyyy',
                              style: TextStyle(
                                color: _startDate != null
                                    ? AppColors.textPrimary
                                    : AppColors.textHint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FormLabel(context.l10n.endDate),
                        GestureDetector(
                          onTap: () => _pickDate(false),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceGrey,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                            child: Text(
                              _endDate != null
                                  ? DateHelper.formatDate(_endDate!)
                                  : 'mm/dd/yyyy',
                              style: TextStyle(
                                color: _endDate != null
                                    ? AppColors.textPrimary
                                    : AppColors.textHint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              FormLabel(context.l10n.storageRegion),
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
                    const Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              FormLabel(context.l10n.descriptionField),
              TextFormField(
                controller: _descriptionCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText:
                      'Detailed technical specifications, history, and physical assessment notes...',
                ),
                validator: AppValidators.validateDescription,
              ),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _submit(false),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isEditMode ? context.l10n.saveChangesButton : context.l10n.postAuction,
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
                      context.l10n.saveAsDraft,
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
}
