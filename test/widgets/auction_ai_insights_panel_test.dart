// test/widgets/auction_ai_insights_panel_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecyamunara/data/models/models.dart';
import 'package:ecyamunara/data/repositories/ai_repository.dart';
import 'package:ecyamunara/l10n/app_localizations.dart';
import 'package:ecyamunara/presentation/screens/client/widgets/auction_ai_insights_panel.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

// Instantly-resolving fake — returns pre-set results or throws.
class _FakeAiRepository implements AiRepository {
  _FakeAiRepository({
    this.insight,
    this.forecast,
    this.shouldThrow = false,
  });
  final Map<String, dynamic>? insight;
  final Map<String, dynamic>? forecast;
  final bool shouldThrow;

  @override
  Future<Map<String, dynamic>?> fetchPriceInsight(AuctionModel _) async {
    if (shouldThrow) throw Exception('Network error');
    return insight;
  }

  @override
  Future<Map<String, dynamic>?> fetchBidForecast(AuctionModel _) async {
    if (shouldThrow) throw Exception('Network error');
    return forecast;
  }
}

// Completer-backed fake — holds futures in pending state until .complete() is
// called. Used to test the shimmer (loading) state.
class _ManualFakeAiRepository implements AiRepository {
  final _insightCompleter = Completer<Map<String, dynamic>?>();
  final _forecastCompleter = Completer<Map<String, dynamic>?>();

  void complete({Map<String, dynamic>? insight, Map<String, dynamic>? forecast}) {
    if (!_insightCompleter.isCompleted) _insightCompleter.complete(insight);
    if (!_forecastCompleter.isCompleted) _forecastCompleter.complete(forecast);
  }

  @override
  Future<Map<String, dynamic>?> fetchPriceInsight(AuctionModel _) =>
      _insightCompleter.future;

  @override
  Future<Map<String, dynamic>?> fetchBidForecast(AuctionModel _) =>
      _forecastCompleter.future;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

AuctionModel _testAuction({double startingPrice = 5_000_000}) => AuctionModel(
      auctionId: 'test-001',
      itemName: 'Toyota Hilux',
      category: 'vehicle',
      plateNumber: 'RAC 000 A',
      condition: 'good',
      description: 'Test',
      photoUrls: const ['photo.jpg'],
      startingPrice: startingPrice,
      currentHighestBid: startingPrice,
      totalBids: 5,
      region: 'Central',
      postedByAdminUid: 'admin-1',
      postedByAdminName: 'Admin',
      auctionStatus: 'active',
      startDate: DateTime(2026, 6, 14),
      endDate: DateTime(2026, 6, 17),
      createdAt: DateTime(2026, 6, 14),
      updatedAt: DateTime(2026, 6, 14),
    );

Widget _wrap(Widget child, AiRepository repo) {
  return ProviderScope(
    overrides: [aiRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  final auction = _testAuction();

  group('AuctionAiInsightsPanel — loading state', () {
    testWidgets('shows AnimatedBuilder shimmer while futures are pending',
        (tester) async {
      final repo = _ManualFakeAiRepository();
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        repo,
      ));
      await tester.pump(); // one frame — futures still unresolved

      expect(find.byType(AnimatedBuilder), findsAtLeastNWidgets(1));
      expect(find.text('AI Insights'), findsNothing);
    });
  });

  group('AuctionAiInsightsPanel — collapse cases', () {
    testWidgets('collapses when both results are null', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(insight: null, forecast: null),
      ));
      await tester.pumpAndSettle();
      expect(find.text('AI Insights'), findsNothing);
    });

    testWidgets('collapses when insight has shadow_mode: true', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: {'shadow_mode': true},
          forecast: {
            'predicted_winning_bid': 6_000_000.0,
            'predicted_probability': 0.7,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('AI Insights'), findsNothing);
    });

    testWidgets('collapses silently when both futures throw', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(shouldThrow: true),
      ));
      await tester.pumpAndSettle();
      expect(find.text('AI Insights'), findsNothing);
    });
  });

  group('AuctionAiInsightsPanel — value signal badges', () {
    testWidgets('shows "Undervalued" badge for undervalued signal',
        (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: {
            'expected_auction_price': 7_000_000.0,
            'value_signal': 'undervalued',
            'value_ratio': 1.4,
            'model_version': 'v1.0.4-synthetic',
            'shadow_mode': false,
          },
          forecast: null,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('AI Insights'), findsOneWidget);
      expect(find.text('Undervalued'), findsOneWidget);
    });

    testWidgets('shows "Overvalued" badge for overvalued signal', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: {
            'expected_auction_price': 3_000_000.0,
            'value_signal': 'overvalued',
            'shadow_mode': false,
          },
          forecast: null,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Overvalued'), findsOneWidget);
    });

    testWidgets('shows "Fair Value" badge for unknown signal string',
        (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: {
            'expected_auction_price': 5_000_000.0,
            'value_signal': 'some_future_unknown_signal',
            'shadow_mode': false,
          },
          forecast: null,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Fair Value'), findsOneWidget);
    });
  });

  group('AuctionAiInsightsPanel — starting price floor clamping', () {
    testWidgets(
        'shows "at least" prefix when predicted bid is below starting price floor',
        (tester) async {
      // startingPrice = 5,000,000; predicted = 3,000,000 → clamped to 5,000,000
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: null,
          forecast: {
            'predicted_winning_bid': 3_000_000.0,
            'predicted_probability': 0.4,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least'), findsOneWidget);
    });

    testWidgets(
        'shows "at least" prefix when predicted bid is within 5% above floor',
        (tester) async {
      // floor = 5,000,000; predicted = 5,100,000 (2% above) → clamped label
      final a = _testAuction(startingPrice: 5_000_000);
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: a.auctionId, auction: a),
        _FakeAiRepository(
          insight: null,
          forecast: {
            'predicted_winning_bid': 5_100_000.0,
            'predicted_probability': 0.5,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least'), findsOneWidget);
    });

    testWidgets('shows bare amount (no prefix) when predicted bid is above floor by > 5%',
        (tester) async {
      // floor = 5,000,000; predicted = 6,000,000 (20% above) → no prefix
      final a = _testAuction(startingPrice: 5_000_000);
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: a.auctionId, auction: a),
        _FakeAiRepository(
          insight: null,
          forecast: {
            'predicted_winning_bid': 6_000_000.0,
            'predicted_probability': 0.6,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least'), findsNothing);
      expect(find.textContaining('RWF'), findsOneWidget);
    });
  });

  group('AuctionAiInsightsPanel — probability bar', () {
    testWidgets('renders probability percentage label', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: null,
          forecast: {
            'predicted_winning_bid': 6_000_000.0,
            'predicted_probability': 0.73,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('73%'), findsOneWidget);
    });

    testWidgets('clamps probability > 1.0 to 100%', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: null,
          forecast: {
            'predicted_winning_bid': 6_000_000.0,
            'predicted_probability': 1.3,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
    });
  });
}
