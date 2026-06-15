// lib/data/repositories/ai_repository.dart
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_constants.dart';
import '../../core/errors/exceptions.dart';
import '../models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AiFeatures — pure static feature builder, no Supabase dependency.
// Tested independently in test/ai/ai_repository_test.dart.
// ─────────────────────────────────────────────────────────────────────────────

class AiFeatures {
  const AiFeatures._();

  static Map<String, dynamic> base(AuctionModel a) => {
        'main_category': a.resolvedMainCategory,
        'sub_category': a.subCategory,
        'brand': a.brand,
        'condition': a.condition,
        'region': a.region,
        'starting_price': a.startingPrice,
        'fuel_type': a.fuelType,
        'transmission': a.transmission,
        'mileage': a.mileage,
        'ownership_history': a.ownershipHistory,
        'accident_history': a.accidentHistory,
        'insurance_status': a.insuranceStatus,
        'asset_age': assetAge(a),
        'auction_duration_hours': durationHours(a),
        'has_description': a.description.isNotEmpty,
        'has_images': a.photoUrls.isNotEmpty,
        'is_mileage_known': a.mileage != null,
        'is_manufacturing_year_known': a.manufacturingYear != null,
        'is_accident_history_known': a.accidentHistory != null,
        'is_insurance_status_known': a.insuranceStatus != null,
      };

  static Map<String, dynamic> forecast(AuctionModel a) {
    final now = DateTime.now();
    final daysUntilClose = max(0.0, a.endDate.difference(now).inHours / 24.0);
    final timeToFirstBidHours = a.timeOfFirstBid != null
        ? a.timeOfFirstBid!.difference(a.startDate).inMinutes / 60.0
        : 0.0;
    final bidMomentum = a.totalBids > 0 && a.timeOfFirstBid != null
        ? a.totalBids / max(1, now.difference(a.timeOfFirstBid!).inHours)
        : 0.0;
    final viewToBidRatio = a.totalBids > 0
        ? a.viewsCount / a.totalBids.toDouble()
        : a.viewsCount.toDouble();
    final isFirstBidQuick = a.timeOfFirstBid != null &&
        a.timeOfFirstBid!.difference(a.startDate).inHours < 2;
    final priceTier = a.startingPrice < 2_000_000
        ? 'low'
        : a.startingPrice < 8_000_000
            ? 'medium'
            : 'high';

    return {
      ...base(a),
      'total_bids': a.totalBids,
      'unique_bidder_count': a.uniqueBidderCount,
      'views_count': a.viewsCount,
      'days_until_close': daysUntilClose,
      'time_to_first_bid_hours': timeToFirstBidHours,
      'bid_momentum': bidMomentum,
      'view_to_bid_ratio': viewToBidRatio,
      'bid_acceleration': 0.5,
      'is_first_bid_quick': isFirstBidQuick,
      'price_tier': priceTier,
    };
  }

  static int assetAge(AuctionModel a) =>
      a.manufacturingYear == null ? 5 : DateTime.now().year - a.manufacturingYear!;

  static double durationHours(AuctionModel a) =>
      a.endDate.difference(a.startDate).inMinutes / 60.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// AiRepository — abstract interface.
// Concrete: AiRepositoryImpl. Fake for tests: implement this interface.
// Returns null when shadow_mode is active (prediction stored, not surfaced).
// Throws AppFunctionException on HTTP errors.
// ─────────────────────────────────────────────────────────────────────────────

abstract class AiRepository {
  Future<Map<String, dynamic>?> fetchPriceInsight(AuctionModel auction);
  Future<Map<String, dynamic>?> fetchBidForecast(AuctionModel auction);
}

class AiRepositoryImpl extends AiRepository {
  AiRepositoryImpl() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>?> fetchPriceInsight(AuctionModel auction) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnAiPredictPrice,
        body: {
          'auction_id': auction.auctionId,
          'store_prediction': true,
          'features': AiFeatures.base(auction),
        },
      );
      if (response.status != 200) {
        final error = (response.data as Map?)?['error'] as String?;
        throw AppFunctionException(error ?? 'AI price insight failed');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['shadow_mode'] == true) return null;
      return data;
    } on AppFunctionException {
      rethrow;
    } catch (e) {
      throw AppFunctionException('AI price insight failed: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchBidForecast(AuctionModel auction) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnAiBidForecast,
        body: {
          'auction_id': auction.auctionId,
          'store_prediction': true,
          'features': AiFeatures.forecast(auction),
        },
      );
      if (response.status != 200) {
        final error = (response.data as Map?)?['error'] as String?;
        throw AppFunctionException(error ?? 'AI bid forecast failed');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['shadow_mode'] == true) return null;
      return data;
    } on AppFunctionException {
      rethrow;
    } catch (e) {
      throw AppFunctionException('AI bid forecast failed: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepositoryImpl(),
);
