// lib/data/models/models.dart
// All Supabase-compatible models. Dates are ISO 8601 strings from PostgreSQL.

// ─────────────────────────────────────────────────────────────────────────────
// AdminPermissions
// ─────────────────────────────────────────────────────────────────────────────
class AdminPermissions {
  final bool postAuctions;
  final bool manageClients;
  final bool viewReports;
  final bool closeAuctions;

  const AdminPermissions({
    this.postAuctions = true,
    this.manageClients = true,
    this.viewReports = true,
    this.closeAuctions = true,
  });

  factory AdminPermissions.fromMap(Map<String, dynamic> map) =>
      AdminPermissions(
        postAuctions: map['post_auctions'] as bool? ?? true,
        manageClients: map['manage_clients'] as bool? ?? true,
        viewReports: map['view_reports'] as bool? ?? true,
        closeAuctions: map['close_auctions'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
    'post_auctions': postAuctions,
    'manage_clients': manageClients,
    'view_reports': viewReports,
    'close_auctions': closeAuctions,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// RegionAdminModel
// ─────────────────────────────────────────────────────────────────────────────
class RegionAdminModel {
  final String uid;
  final String fullNames;
  final String nationalId;
  final String phoneNumber;
  final String region;
  final String role;
  final String accountStatus;
  final String? profilePhotoUrl;
  final String? onesignalPlayerId;
  final AdminPermissions permissions;
  final int totalAuctionsPosted;
  final int totalAuctionsClosed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;
  final String createdBy;

  const RegionAdminModel({
    required this.uid,
    required this.fullNames,
    required this.nationalId,
    required this.phoneNumber,
    required this.region,
    required this.role,
    required this.accountStatus,
    this.profilePhotoUrl,
    this.onesignalPlayerId,
    required this.permissions,
    required this.totalAuctionsPosted,
    required this.totalAuctionsClosed,
    required this.createdAt,
    required this.updatedAt,
    this.lastLogin,
    required this.createdBy,
  });

  factory RegionAdminModel.fromMap(
    Map<String, dynamic> map,
  ) => RegionAdminModel(
    uid: map['id'] as String? ?? '',
    fullNames: map['full_names'] as String? ?? '',
    nationalId: map['national_id'] as String? ?? '',
    phoneNumber: map['phone_number'] as String? ?? '',
    region: map['region'] as String? ?? '',
    role: map['role'] as String? ?? 'region_admin',
    accountStatus: map['account_status'] as String? ?? 'active',
    profilePhotoUrl: map['profile_photo_url'] as String?,
    onesignalPlayerId: map['onesignal_player_id'] as String?,
    permissions: AdminPermissions.fromMap(
      (map['permissions'] as Map<String, dynamic>?) ?? {},
    ),
    totalAuctionsPosted: (map['total_auctions_posted'] as num?)?.toInt() ?? 0,
    totalAuctionsClosed: (map['total_auctions_closed'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(
      map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    updatedAt: DateTime.parse(
      map['updated_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    lastLogin: map['last_login'] != null
        ? DateTime.parse(map['last_login'] as String)
        : null,
    createdBy: map['created_by'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'full_names': fullNames,
    'national_id': nationalId,
    'phone_number': phoneNumber,
    'region': region,
    'role': role,
    'account_status': accountStatus,
    'profile_photo_url': profilePhotoUrl,
    'onesignal_player_id': onesignalPlayerId,
    'permissions': permissions.toMap(),
    'total_auctions_posted': totalAuctionsPosted,
    'total_auctions_closed': totalAuctionsClosed,
    'updated_at': updatedAt.toIso8601String(),
    'last_login': lastLogin?.toIso8601String(),
    'created_by': createdBy,
  };

  bool get isActive => accountStatus == 'active';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is RegionAdminModel && other.uid == uid);
  @override
  int get hashCode => uid.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────
// SuperAdminModel
// ─────────────────────────────────────────────────────────────────────────────
class SuperAdminModel {
  final String uid;
  final String fullNames;
  final String phoneNumber;
  final String role;
  final String accountStatus;
  final String? onesignalPlayerId;
  final String? photoUrl;      // added by migration 20260427000000
  final DateTime createdAt;
  final DateTime? updatedAt;   // added by migration 20260427000000 (nullable for backward compat)
  final DateTime? lastLogin;

  const SuperAdminModel({
    required this.uid,
    required this.fullNames,
    required this.phoneNumber,
    required this.role,
    required this.accountStatus,
    this.onesignalPlayerId,
    this.photoUrl,
    required this.createdAt,
    this.updatedAt,
    this.lastLogin,
  });

  factory SuperAdminModel.fromMap(Map<String, dynamic> map) => SuperAdminModel(
    uid: map['id'] as String? ?? '',
    fullNames: map['full_names'] as String? ?? '',
    phoneNumber: map['phone_number'] as String? ?? '',
    role: map['role'] as String? ?? 'super_admin',
    accountStatus: map['account_status'] as String? ?? 'active',
    onesignalPlayerId: map['onesignal_player_id'] as String?,
    photoUrl: map['photo_url'] as String?,
    createdAt: DateTime.parse(
      map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    updatedAt: map['updated_at'] != null
        ? DateTime.parse(map['updated_at'] as String)
        : null,
    lastLogin: map['last_login'] != null
        ? DateTime.parse(map['last_login'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'full_names': fullNames,
    'phone_number': phoneNumber,
    'role': role,
    'account_status': accountStatus,
    'onesignal_player_id': onesignalPlayerId,
    'photo_url': photoUrl,
    'updated_at': updatedAt?.toIso8601String(),
    'last_login': lastLogin?.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// AuctionModel
// ─────────────────────────────────────────────────────────────────────────────
class AuctionModel {
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
  final DateTime updatedAt;

  // ML-ready structured metadata
  final String? mainCategory;
  final String? subCategory;
  final String? brand;
  final String? model;
  final int? manufacturingYear;
  final String? color;
  final int? mileage;
  final String? fuelType;
  final String? transmission;
  final double? engineSize;
  final int? engineCc;
  final String? drivetrain;
  final int? seatingCapacity;
  final String? frameMaterial;
  final int? gearCount;
  final String? suspensionType;
  final String? brakeType;
  final String? ownershipHistory;
  final String? accidentHistory;
  final String? insuranceStatus;

  const AuctionModel({
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
    required this.updatedAt,
    this.mainCategory,
    this.subCategory,
    this.brand,
    this.model,
    this.manufacturingYear,
    this.color,
    this.mileage,
    this.fuelType,
    this.transmission,
    this.engineSize,
    this.engineCc,
    this.drivetrain,
    this.seatingCapacity,
    this.frameMaterial,
    this.gearCount,
    this.suspensionType,
    this.brakeType,
    this.ownershipHistory,
    this.accidentHistory,
    this.insuranceStatus,
  });

  factory AuctionModel.fromMap(Map<String, dynamic> map) => AuctionModel(
    auctionId:          map['id'] as String? ?? '',
    itemName:           map['item_name'] as String? ?? '',
    category:           map['category'] as String? ?? '',
    plateNumber:        map['plate_number'] as String? ?? '',
    condition:          map['condition'] as String? ?? '',
    description:        map['description'] as String? ?? '',
    photoUrls:          List<String>.from(map['photo_urls'] as List? ?? []),
    startingPrice:      (map['starting_price'] as num?)?.toDouble() ?? 0,
    currentHighestBid:  (map['current_highest_bid'] as num?)?.toDouble() ?? 0,
    currentWinnerUid:   map['current_winner_uid'] as String?,
    currentWinnerName:  map['current_winner_name'] as String?,
    totalBids:          (map['total_bids'] as num?)?.toInt() ?? 0,
    region:             map['region'] as String? ?? '',
    postedByAdminUid:   map['posted_by_admin_uid'] as String? ?? '',
    postedByAdminName:  map['posted_by_admin_name'] as String? ?? '',
    auctionStatus:      map['auction_status'] as String? ?? 'draft',
    startDate: DateTime.parse(
      map['start_date'] as String? ?? DateTime.now().toIso8601String(),
    ),
    endDate: DateTime.parse(
      map['end_date'] as String? ?? DateTime.now().toIso8601String(),
    ),
    closedAt: map['closed_at'] != null
        ? DateTime.parse(map['closed_at'] as String)
        : null,
    winnerUid:      map['winner_uid'] as String?,
    winnerName:     map['winner_name'] as String?,
    winningAmount:  (map['winning_amount'] as num?)?.toDouble(),
    createdAt: DateTime.parse(
      map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    updatedAt: DateTime.parse(
      map['updated_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    mainCategory:     map['main_category'] as String?,
    subCategory:      map['sub_category'] as String?,
    brand:            map['brand'] as String?,
    model:            map['model'] as String?,
    manufacturingYear:(map['manufacturing_year'] as num?)?.toInt(),
    color:            map['color'] as String?,
    mileage:          (map['mileage'] as num?)?.toInt(),
    fuelType:         map['fuel_type'] as String?,
    transmission:     map['transmission'] as String?,
    engineSize:       (map['engine_size'] as num?)?.toDouble(),
    engineCc:         (map['engine_cc'] as num?)?.toInt(),
    drivetrain:       map['drivetrain'] as String?,
    seatingCapacity:  (map['seating_capacity'] as num?)?.toInt(),
    frameMaterial:    map['frame_material'] as String?,
    gearCount:        (map['gear_count'] as num?)?.toInt(),
    suspensionType:   map['suspension_type'] as String?,
    brakeType:        map['brake_type'] as String?,
    ownershipHistory: map['ownership_history'] as String?,
    accidentHistory:  map['accident_history'] as String?,
    insuranceStatus:  map['insurance_status'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'item_name':            itemName,
    'category':             category,
    'plate_number':         plateNumber,
    'condition':            condition,
    'description':          description,
    'photo_urls':           photoUrls,
    'starting_price':       startingPrice,
    'current_highest_bid':  currentHighestBid,
    'current_winner_uid':   currentWinnerUid,
    'current_winner_name':  currentWinnerName,
    'total_bids':           totalBids,
    'region':               region,
    'posted_by_admin_uid':  postedByAdminUid,
    'posted_by_admin_name': postedByAdminName,
    'auction_status':       auctionStatus,
    'start_date':           startDate.toIso8601String(),
    'end_date':             endDate.toIso8601String(),
    'closed_at':            closedAt?.toIso8601String(),
    'winner_uid':           winnerUid,
    'winner_name':          winnerName,
    'winning_amount':       winningAmount,
    'updated_at':           updatedAt.toIso8601String(),
    if (mainCategory != null)     'main_category':      mainCategory,
    if (subCategory != null)      'sub_category':       subCategory,
    if (brand != null)            'brand':              brand,
    if (model != null)            'model':              model,
    if (manufacturingYear != null)'manufacturing_year': manufacturingYear,
    if (color != null)            'color':              color,
    if (mileage != null)          'mileage':            mileage,
    if (fuelType != null)         'fuel_type':          fuelType,
    if (transmission != null)     'transmission':       transmission,
    if (engineSize != null)       'engine_size':        engineSize,
    if (engineCc != null)         'engine_cc':          engineCc,
    if (drivetrain != null)       'drivetrain':         drivetrain,
    if (seatingCapacity != null)  'seating_capacity':   seatingCapacity,
    if (frameMaterial != null)    'frame_material':     frameMaterial,
    if (gearCount != null)        'gear_count':         gearCount,
    if (suspensionType != null)   'suspension_type':    suspensionType,
    if (brakeType != null)        'brake_type':         brakeType,
    if (ownershipHistory != null) 'ownership_history':  ownershipHistory,
    if (accidentHistory != null)  'accident_history':   accidentHistory,
    if (insuranceStatus != null)  'insurance_status':   insuranceStatus,
  };

  AuctionModel copyWith({
    String? itemName,
    String? category,
    String? plateNumber,
    String? condition,
    String? description,
    List<String>? photoUrls,
    double? startingPrice,
    double? currentHighestBid,
    String? currentWinnerUid,
    String? currentWinnerName,
    int? totalBids,
    String? region,
    String? postedByAdminUid,
    String? postedByAdminName,
    String? auctionStatus,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? closedAt,
    String? winnerUid,
    String? winnerName,
    double? winningAmount,
    DateTime? updatedAt,
    String? mainCategory,
    String? subCategory,
    String? brand,
    String? model,
    int? manufacturingYear,
    String? color,
    int? mileage,
    String? fuelType,
    String? transmission,
    double? engineSize,
    int? engineCc,
    String? drivetrain,
    int? seatingCapacity,
    String? frameMaterial,
    int? gearCount,
    String? suspensionType,
    String? brakeType,
    String? ownershipHistory,
    String? accidentHistory,
    String? insuranceStatus,
  }) => AuctionModel(
    auctionId:          auctionId,
    itemName:           itemName ?? this.itemName,
    category:           category ?? this.category,
    plateNumber:        plateNumber ?? this.plateNumber,
    condition:          condition ?? this.condition,
    description:        description ?? this.description,
    photoUrls:          photoUrls ?? this.photoUrls,
    startingPrice:      startingPrice ?? this.startingPrice,
    currentHighestBid:  currentHighestBid ?? this.currentHighestBid,
    currentWinnerUid:   currentWinnerUid ?? this.currentWinnerUid,
    currentWinnerName:  currentWinnerName ?? this.currentWinnerName,
    totalBids:          totalBids ?? this.totalBids,
    region:             region ?? this.region,
    postedByAdminUid:   postedByAdminUid ?? this.postedByAdminUid,
    postedByAdminName:  postedByAdminName ?? this.postedByAdminName,
    auctionStatus:      auctionStatus ?? this.auctionStatus,
    startDate:          startDate ?? this.startDate,
    endDate:            endDate ?? this.endDate,
    closedAt:           closedAt ?? this.closedAt,
    winnerUid:          winnerUid ?? this.winnerUid,
    winnerName:         winnerName ?? this.winnerName,
    winningAmount:      winningAmount ?? this.winningAmount,
    createdAt:          createdAt,
    updatedAt:          updatedAt ?? this.updatedAt,
    mainCategory:       mainCategory ?? this.mainCategory,
    subCategory:        subCategory ?? this.subCategory,
    brand:              brand ?? this.brand,
    model:              model ?? this.model,
    manufacturingYear:  manufacturingYear ?? this.manufacturingYear,
    color:              color ?? this.color,
    mileage:            mileage ?? this.mileage,
    fuelType:           fuelType ?? this.fuelType,
    transmission:       transmission ?? this.transmission,
    engineSize:         engineSize ?? this.engineSize,
    engineCc:           engineCc ?? this.engineCc,
    drivetrain:         drivetrain ?? this.drivetrain,
    seatingCapacity:    seatingCapacity ?? this.seatingCapacity,
    frameMaterial:      frameMaterial ?? this.frameMaterial,
    gearCount:          gearCount ?? this.gearCount,
    suspensionType:     suspensionType ?? this.suspensionType,
    brakeType:          brakeType ?? this.brakeType,
    ownershipHistory:   ownershipHistory ?? this.ownershipHistory,
    accidentHistory:    accidentHistory ?? this.accidentHistory,
    insuranceStatus:    insuranceStatus ?? this.insuranceStatus,
  );

  bool get isActive => auctionStatus == 'active';
  bool get isClosed => auctionStatus == 'closed';
  bool get isExpired => DateTime.now().isAfter(endDate);

  // Resolved main category — falls back to legacy 'category' field for old records
  String get resolvedMainCategory =>
      mainCategory?.isNotEmpty == true ? mainCategory! : category;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuctionModel && other.auctionId == auctionId);
  @override
  int get hashCode => auctionId.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────
// BidModel
// ─────────────────────────────────────────────────────────────────────────────
class BidModel {
  final String bidId;
  final String auctionId;
  final String bidderUid;
  final String bidderName;
  final String bidderPhone;
  final String bidderDistrict;
  final double bidAmount;
  final String bidStatus;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const BidModel({
    required this.bidId,
    required this.auctionId,
    required this.bidderUid,
    required this.bidderName,
    required this.bidderPhone,
    required this.bidderDistrict,
    required this.bidAmount,
    required this.bidStatus,
    required this.createdAt,
    this.updatedAt,
  });

  factory BidModel.fromMap(Map<String, dynamic> map) => BidModel(
    bidId:          map['id'] as String? ?? '',
    auctionId:      map['auction_id'] as String? ?? '',
    bidderUid:      map['bidder_uid'] as String? ?? '',
    bidderName:     map['bidder_name'] as String? ?? '',
    bidderPhone:    map['bidder_phone'] as String? ?? '',
    bidderDistrict: map['bidder_district'] as String? ?? '',
    bidAmount:      (map['bid_amount'] as num?)?.toDouble() ?? 0,
    bidStatus:      map['bid_status'] as String? ?? 'outbid',
    createdAt:      DateTime.parse(
      map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    updatedAt: map['updated_at'] != null
        ? DateTime.parse(map['updated_at'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'auction_id':      auctionId,
    'bidder_uid':      bidderUid,
    'bidder_name':     bidderName,
    'bidder_phone':    bidderPhone,
    'bidder_district': bidderDistrict,
    'bid_amount':      bidAmount,
    'bid_status':      bidStatus,
  };

  bool get isWinning => bidStatus == 'winning';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is BidModel && other.bidId == bidId);
  @override
  int get hashCode => bidId.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────
// FeedbackModel
// ─────────────────────────────────────────────────────────────────────────────
class FeedbackModel {
  final String feedbackId;
  final String clientUid;
  final String clientName;
  final String? clientPhotoUrl;
  final String auctionId;
  final String itemName;
  final String region;
  final int starRating;
  final List<String> selectedTags;
  final String comment;
  final bool wouldRecommend;
  final DateTime createdAt;
  final bool isRead;

  const FeedbackModel({
    required this.feedbackId,
    required this.clientUid,
    required this.clientName,
    this.clientPhotoUrl,
    required this.auctionId,
    required this.itemName,
    required this.region,
    required this.starRating,
    required this.selectedTags,
    required this.comment,
    required this.wouldRecommend,
    required this.createdAt,
    this.isRead = false,
  });

  factory FeedbackModel.fromMap(Map<String, dynamic> map) => FeedbackModel(
    feedbackId: map['id'] as String? ?? '',
    clientUid: map['client_uid'] as String? ?? '',
    clientName: map['client_name'] as String? ?? '',
    // Populated when the query joins users!client_uid(profile_photo_url)
    clientPhotoUrl:
        (map['users'] as Map<String, dynamic>?)?['profile_photo_url']
            as String?,
    auctionId: map['auction_id'] as String? ?? '',
    itemName: map['item_name'] as String? ?? '',
    region: map['region'] as String? ?? '',
    starRating: (map['star_rating'] as num?)?.toInt() ?? 1,
    selectedTags: List<String>.from(map['selected_tags'] as List? ?? []),
    comment: map['comment'] as String? ?? '',
    wouldRecommend: map['would_recommend'] as bool? ?? false,
    createdAt: DateTime.parse(
      map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    isRead: map['is_read'] as bool? ?? false,
  );

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'client_uid': clientUid,
      'client_name': clientName,
      'item_name': itemName,
      'region': region,
      'star_rating': starRating,
      'selected_tags': selectedTags,
      'comment': comment,
      'would_recommend': wouldRecommend,
    };
    if (auctionId.isNotEmpty) map['auction_id'] = auctionId;
    return map;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppSettingsModel
// ─────────────────────────────────────────────────────────────────────────────
class AppSettingsModel {
  final String id;
  final String appVersion;
  final bool maintenanceMode;
  final double maxBidIncrement;
  final bool auctionAutoClose;
  final bool notificationEnabled;
  final DateTime updatedAt;
  final String? updatedBy;

  const AppSettingsModel({
    this.id = 'config',
    this.appVersion = '1.0.0',
    this.maintenanceMode = false,
    this.maxBidIncrement = 10000,
    this.auctionAutoClose = true,
    this.notificationEnabled = true,
    required this.updatedAt,
    this.updatedBy,
  });

  factory AppSettingsModel.fromMap(Map<String, dynamic> map) => AppSettingsModel(
    id: map['id'] as String? ?? 'config',
    appVersion: map['app_version'] as String? ?? '1.0.0',
    maintenanceMode: map['maintenance_mode'] as bool? ?? false,
    maxBidIncrement:
        (map['max_bid_increment'] as num?)?.toDouble() ?? 10000,
    auctionAutoClose: map['auction_auto_close'] as bool? ?? true,
    notificationEnabled: map['notification_enabled'] as bool? ?? true,
    updatedAt: DateTime.parse(
      map['updated_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    updatedBy: map['updated_by'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'app_version': appVersion,
    'maintenance_mode': maintenanceMode,
    'max_bid_increment': maxBidIncrement,
    'auction_auto_close': auctionAutoClose,
    'notification_enabled': notificationEnabled,
    'updated_at': DateTime.now().toIso8601String(),
  };

  AppSettingsModel copyWith({
    String? appVersion,
    bool? maintenanceMode,
    double? maxBidIncrement,
    bool? auctionAutoClose,
    bool? notificationEnabled,
  }) =>
      AppSettingsModel(
        id: id,
        appVersion: appVersion ?? this.appVersion,
        maintenanceMode: maintenanceMode ?? this.maintenanceMode,
        maxBidIncrement: maxBidIncrement ?? this.maxBidIncrement,
        auctionAutoClose: auctionAutoClose ?? this.auctionAutoClose,
        notificationEnabled: notificationEnabled ?? this.notificationEnabled,
        updatedAt: updatedAt,
        updatedBy: updatedBy,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DistrictModel
// ─────────────────────────────────────────────────────────────────────────────
class DistrictModel {
  final String districtName;
  final String province;
  final String region;

  const DistrictModel({
    required this.districtName,
    required this.province,
    required this.region,
  });

  factory DistrictModel.fromMap(Map<String, dynamic> map) => DistrictModel(
    districtName: map['district_name'] as String? ?? '',
    province: map['province'] as String? ?? '',
    region: map['region'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'district_name': districtName,
    'province': province,
    'region': region,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// NotificationModel
// ─────────────────────────────────────────────────────────────────────────────
class NotificationModel {
  final String notificationId;
  final String userUid;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final String? auctionId;
  final DateTime createdAt;

  const NotificationModel({
    required this.notificationId,
    required this.userUid,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    this.auctionId,
    required this.createdAt,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map) =>
      NotificationModel(
        notificationId: map['id'] as String? ?? '',
        userUid: map['user_uid'] as String? ?? '',
        title: map['title'] as String? ?? '',
        body: map['body'] as String? ?? '',
        type: map['type'] as String? ?? 'system',
        isRead: map['is_read'] as bool? ?? false,
        auctionId: map['auction_id'] as String?,
        createdAt: DateTime.parse(
          map['created_at'] as String? ?? DateTime.now().toIso8601String(),
        ),
      );

  Map<String, dynamic> toMap() => {
    'user_uid': userUid,
    'title': title,
    'body': body,
    'type': type,
    'is_read': isRead,
    'auction_id': auctionId,
  };

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
    notificationId: notificationId,
    userUid: userUid,
    title: title,
    body: body,
    type: type,
    isRead: isRead ?? this.isRead,
    auctionId: auctionId,
    createdAt: createdAt,
  );
}

