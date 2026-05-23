// ════════════════════════════════════════════════════════
// lib/core/constants/app_constants.dart
// ════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const primaryBlue = Color(0xFF003087);
  static const gold = Color(0xFFFFD700);
  static const darkBlue = Color(0xFF001F5B);
  static const success = Color(0xFF2E7D32);
  static const error = Color(0xFFC62828);
  static const warning = Color(0xFFE65100);
  static const background = Color(0xFFF5F5F5);
  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
}

class AppStrings {
  AppStrings._();
  static const appName = 'E-CYAMUNARA';
  static const appTagline = 'Rwanda National Police Auction Platform';
  static const login = 'Log In';
  static const register = 'Create Account';
  static const logout = 'Log Out';
  static const phoneNumber = 'Phone Number';
  static const password = 'Password';
  static const confirmPassword = 'Confirm Password';
  static const fullNames = 'Full Names';
  static const nationalId = 'National ID (16 digits)';
  static const district = 'Select District';
  static const selectRegion = 'Select Your Region';
  static const auctions = 'Auctions';
  static const startingPrice = 'Starting Price';
  static const currentBid = 'Current Highest Bid';
  static const placeBid = 'Place Bid';
  static const bidAmount = 'Your Bid Amount (RWF)';
  static const auctionEndsIn = 'Ends in';
  static const noBids = 'No bids yet — be the first!';
  static const noAuctions = 'No active auctions in your region';
  static const networkError = 'Check your internet connection';
  static const genericError = 'Something went wrong. Please try again';
}
