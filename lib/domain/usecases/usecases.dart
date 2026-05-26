// lib/domain/usecases/usecases.dart
import '../../core/errors/exceptions.dart';
import '../../core/errors/failures.dart';
import '../../data/models/models.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/auction_repository.dart';
import '../../data/repositories/repositories.dart';

// ── AUTH ──────────────────────────────────────────────────────────────────────

class RegisterClientUseCase {
  const RegisterClientUseCase(this._repo);
  final AuthRepository _repo;

  Future<(UserModel?, Failure?)> call({
    required String fullNames,
    required String nationalId,
    required String phoneNumber,
    required String district,
    required String province,
    required String region,
    required String password,
  }) async {
    try {
      final user = await _repo.registerClient(
        fullNames: fullNames,
        nationalId: nationalId,
        phoneNumber: phoneNumber,
        district: district,
        province: province,
        region: region,
        password: password,
      );
      return (user, null);
    } on AppAuthException catch (e) {
      return (null, AuthFailure(e.message));
    } on DatabaseException catch (e) {
      return (null, DatabaseFailure(e.message));
    } catch (e) {
      return (null, UnknownFailure(e.toString()));
    }
  }
}

class LoginUseCase {
  const LoginUseCase(this._repo);
  final AuthRepository _repo;

  Future<(String?, Failure?)> call({
    required String phoneNumber,
    required String password,
    required bool isAdmin,
  }) async {
    try {
      final role = isAdmin
          ? await _repo.loginAdmin(phoneNumber: phoneNumber, password: password)
          : await _repo.loginClient(
              phoneNumber: phoneNumber,
              password: password,
            );
      return (role, null);
    } on AppAuthException catch (e) {
      return (null, AuthFailure(e.message));
    } catch (e) {
      return (null, UnknownFailure(e.toString()));
    }
  }
}

class LogoutUseCase {
  const LogoutUseCase(this._repo);
  final AuthRepository _repo;

  Future<Failure?> call() async {
    try {
      await _repo.logout();
      return null;
    } on AppAuthException catch (e) {
      return AuthFailure(e.message);
    } catch (e) {
      return UnknownFailure(e.toString());
    }
  }
}

class ForgotPasswordUseCase {
  const ForgotPasswordUseCase(this._repo);
  final AuthRepository _repo;

  Future<Failure?> call({
    required String phoneNumber,
    required String newPassword,
  }) async {
    try {
      await _repo.resetClientPassword(
        phoneNumber: phoneNumber,
        newPassword: newPassword,
      );
      return null;
    } on AppAuthException catch (e) {
      return AuthFailure(e.message);
    } catch (e) {
      return UnknownFailure(e.toString());
    }
  }
}

class LoginUnifiedUseCase {
  const LoginUnifiedUseCase(this._repo);
  final AuthRepository _repo;

  Future<(String?, Failure?)> call({
    required String phoneNumber,
    required String password,
  }) async {
    try {
      final role = await _repo.loginUnified(
        phoneNumber: phoneNumber,
        password: password,
      );
      return (role, null);
    } on AppAuthException catch (e) {
      return (null, AuthFailure(e.message));
    } catch (e) {
      return (null, UnknownFailure(e.toString()));
    }
  }
}

// ── AUCTION ───────────────────────────────────────────────────────────────────

class GetAuctionsUseCase {
  const GetAuctionsUseCase(this._repo);
  final AuctionRepository _repo;

  Stream<List<AuctionModel>> call(String region, {String? category}) =>
      _repo.getAuctionsByRegion(region, category: category);
}

class GetAuctionDetailUseCase {
  const GetAuctionDetailUseCase(this._repo);
  final AuctionRepository _repo;

  Future<(AuctionModel?, Failure?)> call(String auctionId) async {
    try {
      final a = await _repo.getAuctionById(auctionId);
      return (a, null);
    } on DatabaseException catch (e) {
      return (null, DatabaseFailure(e.message));
    } catch (e) {
      return (null, UnknownFailure(e.toString()));
    }
  }
}

class PostAuctionUseCase {
  const PostAuctionUseCase(this._repo);
  final AuctionRepository _repo;

  Future<(AuctionModel?, Failure?)> call(
    AuctionModel auction,
    List<dynamic> photos,
  ) async {
    try {
      final posted = await _repo.postAuction(auction, photos.cast());
      return (posted, null);
    } on ValidationException catch (e) {
      return (null, ValidationFailure(e.message));
    } on DatabaseException catch (e) {
      return (null, DatabaseFailure(e.message));
    } on AppStorageException catch (e) {
      return (null, StorageFailure(e.message));
    } catch (e) {
      return (null, UnknownFailure(e.toString()));
    }
  }
}

class UpdateAuctionUseCase {
  const UpdateAuctionUseCase(this._repo);
  final AuctionRepository _repo;

  Future<Failure?> call(AuctionModel auction) async {
    try {
      await _repo.updateAuction(auction);
      return null;
    } on DatabaseException catch (e) {
      return DatabaseFailure(e.message);
    } catch (e) {
      return UnknownFailure(e.toString());
    }
  }
}

class DeleteAuctionUseCase {
  const DeleteAuctionUseCase(this._repo);
  final AuctionRepository _repo;

  Future<Failure?> call(String auctionId) async {
    try {
      await _repo.deleteAuction(auctionId);
      return null;
    } on DatabaseException catch (e) {
      return DatabaseFailure(e.message);
    } catch (e) {
      return UnknownFailure(e.toString());
    }
  }
}

class CloseAuctionUseCase {
  const CloseAuctionUseCase(this._repo);
  final AdminRepository _repo;

  Future<(Map<String, dynamic>?, Failure?)> call(String auctionId) async {
    try {
      final result = await _repo.closeAuctionManually(auctionId);
      return (result, null);
    } on AppFunctionException catch (e) {
      return (null, FunctionFailure(e.message));
    } catch (e) {
      return (null, UnknownFailure(e.toString()));
    }
  }
}

// ── BID ───────────────────────────────────────────────────────────────────────

class PlaceBidUseCase {
  const PlaceBidUseCase(this._repo);
  final BidRepository _repo;

  Future<(Map<String, dynamic>?, Failure?)> call({
    required String auctionId,
    required double bidAmount,
    required String bidderUid,
  }) async {
    try {
      final result = await _repo.placeBid(
        auctionId: auctionId,
        bidAmount: bidAmount,
        bidderUid: bidderUid,
      );
      return (result, null);
    } on AppFunctionException catch (e) {
      return (null, FunctionFailure(e.message));
    } catch (e) {
      return (null, UnknownFailure(e.toString()));
    }
  }
}

class GetBidsUseCase {
  const GetBidsUseCase(this._repo);
  final BidRepository _repo;

  Stream<List<BidModel>> callForAuction(String auctionId) =>
      _repo.getBidsForAuction(auctionId);

  Future<(List<BidModel>?, Failure?)> callForClient(String clientUid) async {
    try {
      final bids = await _repo.getClientBids(clientUid);
      return (bids, null);
    } on DatabaseException catch (e) {
      return (null, DatabaseFailure(e.message));
    } catch (e) {
      return (null, UnknownFailure(e.toString()));
    }
  }
}

// ── ADMIN ─────────────────────────────────────────────────────────────────────

class CreateAdminUseCase {
  const CreateAdminUseCase(this._repo);
  final AdminRepository _repo;

  Future<Failure?> call(RegionAdminModel admin) async {
    try {
      await _repo.createRegionAdmin(admin);
      return null;
    } on AppFunctionException catch (e) {
      return FunctionFailure(e.message);
    } catch (e) {
      return UnknownFailure(e.toString());
    }
  }
}

class ManageUserUseCase {
  const ManageUserUseCase(this._repo);
  final UserRepository _repo;

  Future<Failure?> suspend(String uid, String reason) async {
    try {
      await _repo.suspendUser(uid, reason);
      return null;
    } on AppFunctionException catch (e) {
      return FunctionFailure(e.message);
    } catch (e) {
      return UnknownFailure(e.toString());
    }
  }

  Future<Failure?> activate(String uid) async {
    try {
      await _repo.activateUser(uid);
      return null;
    } on AppFunctionException catch (e) {
      return FunctionFailure(e.message);
    } catch (e) {
      return UnknownFailure(e.toString());
    }
  }
}
