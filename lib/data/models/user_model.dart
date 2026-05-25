// lib/data/models/user_model.dart
// Supabase returns plain Map<String, dynamic> JSON from PostgreSQL.
// No Timestamp class needed — dates come as ISO 8601 strings.

class UserModel {
  final String uid;
  final String fullNames;
  final String nationalId; // AES-256 encrypted
  final String phoneNumber;
  final String district;
  final String province;
  final String region;
  final String role;
  final String accountStatus;
  final String? profilePhotoUrl;
  final String? onesignalPlayerId; // replaces fcm_token
  final int totalBidsPlaced;
  final int totalAuctionsWon;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  const UserModel({
    required this.uid,
    required this.fullNames,
    required this.nationalId,
    required this.phoneNumber,
    required this.district,
    required this.province,
    required this.region,
    required this.role,
    required this.accountStatus,
    this.profilePhotoUrl,
    this.onesignalPlayerId,
    required this.totalBidsPlaced,
    required this.totalAuctionsWon,
    required this.createdAt,
    required this.updatedAt,
    this.lastLogin,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['id'] as String? ?? '',
      fullNames: map['full_names'] as String? ?? '',
      nationalId: map['national_id'] as String? ?? '',
      phoneNumber: map['phone_number'] as String? ?? '',
      district: map['district'] as String? ?? '',
      province: map['province'] as String? ?? '',
      region: map['region'] as String? ?? '',
      role: map['role'] as String? ?? 'client',
      accountStatus: map['account_status'] as String? ?? 'active',
      profilePhotoUrl: map['profile_photo_url'] as String?,
      onesignalPlayerId: map['onesignal_player_id'] as String?,
      totalBidsPlaced: (map['total_bids_placed'] as num?)?.toInt() ?? 0,
      totalAuctionsWon: (map['total_auctions_won'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(
        map['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        map['updated_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      lastLogin: map['last_login'] != null
          ? DateTime.parse(map['last_login'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'full_names': fullNames,
    'national_id': nationalId,
    'phone_number': phoneNumber,
    'district': district,
    'province': province,
    'region': region,
    'role': role,
    'account_status': accountStatus,
    'profile_photo_url': profilePhotoUrl,
    'onesignal_player_id': onesignalPlayerId,
    'total_bids_placed': totalBidsPlaced,
    'total_auctions_won': totalAuctionsWon,
    'updated_at': updatedAt.toIso8601String(),
    'last_login': lastLogin?.toIso8601String(),
  };

  UserModel copyWith({
    String? fullNames,
    String? nationalId,
    String? phoneNumber,
    String? district,
    String? province,
    String? region,
    String? role,
    String? accountStatus,
    String? profilePhotoUrl,
    String? onesignalPlayerId,
    int? totalBidsPlaced,
    int? totalAuctionsWon,
    DateTime? updatedAt,
    DateTime? lastLogin,
  }) {
    return UserModel(
      uid: uid,
      fullNames: fullNames ?? this.fullNames,
      nationalId: nationalId ?? this.nationalId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      district: district ?? this.district,
      province: province ?? this.province,
      region: region ?? this.region,
      role: role ?? this.role,
      accountStatus: accountStatus ?? this.accountStatus,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      onesignalPlayerId: onesignalPlayerId ?? this.onesignalPlayerId,
      totalBidsPlaced: totalBidsPlaced ?? this.totalBidsPlaced,
      totalAuctionsWon: totalAuctionsWon ?? this.totalAuctionsWon,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }

  bool get isActive => accountStatus == 'active';
  bool get isSuspended => accountStatus == 'suspended';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UserModel && other.uid == uid);
  @override
  int get hashCode => uid.hashCode;
}
