// lib/domain/entities/entities.dart
//
// Pure Dart entity classes — zero external dependencies.
// Repositories convert between data models and these entities.
// Use-cases and UI work exclusively with entities.

class UserEntity {
  final String uid;
  final String fullNames;
  final String phoneNumber;
  final String district;
  final String province;
  final String region;
  final String role;
  final String accountStatus;
  final String? profilePhotoUrl;
  final int totalBidsPlaced;
  final int totalAuctionsWon;
  final DateTime createdAt;
  final DateTime? lastLogin;

  const UserEntity({
    required this.uid,
    required this.fullNames,
    required this.phoneNumber,
    required this.district,
    required this.province,
    required this.region,
    required this.role,
    required this.accountStatus,
    this.profilePhotoUrl,
    required this.totalBidsPlaced,
    required this.totalAuctionsWon,
    required this.createdAt,
    this.lastLogin,
  });

  bool get isActive => accountStatus == 'active';
  bool get isSuspended => accountStatus == 'suspended';
  bool get isClient => role == 'client';
  bool get isRegionAdmin => role == 'region_admin';
  bool get isSuperAdmin => role == 'super_admin';
}

class AuctionEntity {
  final String auctionId;
  final String itemName;
  final String category;
  final String plateNumber;
  final String condition;
  final String description;
  final List<String> photoUrls;
  final double startingPrice;
  final double currentHighestBid;
  final String? currentWinnerUid;
  final String? currentWinnerName;
  final int totalBids;
  final String region;
  final String postedByAdminUid;
  final String postedByAdminName;
  final String auctionStatus;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime? closedAt;
  final String? winnerUid;
  final String? winnerName;
  final double? winningAmount;
  final DateTime createdAt;

  const AuctionEntity({
    required this.auctionId,
    required this.itemName,
    required this.category,
    required this.plateNumber,
    required this.condition,
    required this.description,
    required this.photoUrls,
    required this.startingPrice,
    required this.currentHighestBid,
    this.currentWinnerUid,
    this.currentWinnerName,
    required this.totalBids,
    required this.region,
    required this.postedByAdminUid,
    required this.postedByAdminName,
    required this.auctionStatus,
    required this.startDate,
    required this.endDate,
    this.closedAt,
    this.winnerUid,
    this.winnerName,
    this.winningAmount,
    required this.createdAt,
  });

  bool get isActive => auctionStatus == 'active';
  bool get isClosed => auctionStatus == 'closed';
  bool get isExpired => DateTime.now().isAfter(endDate);
  bool get hasBids => totalBids > 0;
}

class BidEntity {
  final String bidId;
  final String auctionId;
  final String bidderUid;
  final String bidderName;
  final String bidderPhone;
  final String bidderDistrict;
  final double bidAmount;
  final String bidStatus;
  final DateTime createdAt;

  const BidEntity({
    required this.bidId,
    required this.auctionId,
    required this.bidderUid,
    required this.bidderName,
    required this.bidderPhone,
    required this.bidderDistrict,
    required this.bidAmount,
    required this.bidStatus,
    required this.createdAt,
  });

  bool get isWinning => bidStatus == 'winning';
}

class NotificationEntity {
  final String notificationId;
  final String userUid;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final String? auctionId;
  final DateTime createdAt;

  const NotificationEntity({
    required this.notificationId,
    required this.userUid,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    this.auctionId,
    required this.createdAt,
  });
}

class FeedbackEntity {
  final String feedbackId;
  final String clientUid;
  final String clientName;
  final String auctionId;
  final String itemName;
  final String region;
  final int starRating;
  final List<String> selectedTags;
  final String comment;
  final bool wouldRecommend;
  final DateTime createdAt;

  const FeedbackEntity({
    required this.feedbackId,
    required this.clientUid,
    required this.clientName,
    required this.auctionId,
    required this.itemName,
    required this.region,
    required this.starRating,
    required this.selectedTags,
    required this.comment,
    required this.wouldRecommend,
    required this.createdAt,
  });
}

class RegionAdminEntity {
  final String uid;
  final String fullNames;
  final String phoneNumber;
  final String region;
  final String accountStatus;
  final Map<String, bool> permissions;
  final int totalAuctionsPosted;
  final int totalAuctionsClosed;
  final DateTime createdAt;
  final String createdBy;

  const RegionAdminEntity({
    required this.uid,
    required this.fullNames,
    required this.phoneNumber,
    required this.region,
    required this.accountStatus,
    required this.permissions,
    required this.totalAuctionsPosted,
    required this.totalAuctionsClosed,
    required this.createdAt,
    required this.createdBy,
  });

  bool get isActive => accountStatus == 'active';
  bool get canPostAuctions => permissions['post_auctions'] ?? true;
  bool get canManageClients => permissions['manage_clients'] ?? true;
  bool get canViewReports => permissions['view_reports'] ?? true;
  bool get canCloseAuctions => permissions['close_auctions'] ?? true;
}
