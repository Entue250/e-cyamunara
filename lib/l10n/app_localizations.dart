import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_rw.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('rw'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'E-CYAMUNARA'**
  String get appTitle;

  /// No description provided for @appSubtitle.
  ///
  /// In en, this message translates to:
  /// **'ONLINE VEHICLE AUCTION PLATFORM'**
  String get appSubtitle;

  /// No description provided for @officialSystem.
  ///
  /// In en, this message translates to:
  /// **'OFFICIAL RNP E-AUCTION SYSTEM'**
  String get officialSystem;

  /// Login screen title
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Access your police-backed auction account.'**
  String get loginSubtitle;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'LOGIN'**
  String get loginButton;

  /// No description provided for @loginAsAdmin.
  ///
  /// In en, this message translates to:
  /// **'LOGIN AS ADMIN'**
  String get loginAsAdmin;

  /// No description provided for @adminLogin.
  ///
  /// In en, this message translates to:
  /// **'Admin Login'**
  String get adminLogin;

  /// No description provided for @adminPortal.
  ///
  /// In en, this message translates to:
  /// **'POLICE REGION ADMIN PORTAL'**
  String get adminPortal;

  /// No description provided for @authorizedOnly.
  ///
  /// In en, this message translates to:
  /// **'Authorized Personnel Only'**
  String get authorizedOnly;

  /// No description provided for @adminSecurityNote.
  ///
  /// In en, this message translates to:
  /// **'This portal is for authorized Rwanda National Police officers only. Any unauthorized access attempts are monitored and logged.'**
  String get adminSecurityNote;

  /// No description provided for @backToClientLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to Client Login'**
  String get backToClientLogin;

  /// Register nav link
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Register to start bidding'**
  String get registerSubtitle;

  /// No description provided for @registerButton.
  ///
  /// In en, this message translates to:
  /// **'REGISTER'**
  String get registerButton;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// No description provided for @noAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get noAccount;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'PHONE NUMBER'**
  String get phoneNumber;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumberLabel;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'PASSWORD'**
  String get password;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM PASSWORD'**
  String get confirmPassword;

  /// No description provided for @fullNames.
  ///
  /// In en, this message translates to:
  /// **'FULL NAMES'**
  String get fullNames;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @nationalId.
  ///
  /// In en, this message translates to:
  /// **'NATIONAL ID'**
  String get nationalId;

  /// No description provided for @nationalIdLabel.
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get nationalIdLabel;

  /// No description provided for @nationalIdCannotChange.
  ///
  /// In en, this message translates to:
  /// **'National ID cannot be changed after creation'**
  String get nationalIdCannotChange;

  /// No description provided for @district.
  ///
  /// In en, this message translates to:
  /// **'DISTRICT'**
  String get district;

  /// No description provided for @selectDistrict.
  ///
  /// In en, this message translates to:
  /// **'SELECT YOUR DISTRICT'**
  String get selectDistrict;

  /// No description provided for @selectDistrictHint.
  ///
  /// In en, this message translates to:
  /// **'Select district'**
  String get selectDistrictHint;

  /// No description provided for @pleaseSelectDistrict.
  ///
  /// In en, this message translates to:
  /// **'Please select your district'**
  String get pleaseSelectDistrict;

  /// No description provided for @forgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot?'**
  String get forgot;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get or;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @resetPasswordButton.
  ///
  /// In en, this message translates to:
  /// **'RESET PASSWORD'**
  String get resetPasswordButton;

  /// No description provided for @passwordResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password reset successfully. Check your SMS.'**
  String get passwordResetSuccess;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPassword;

  /// No description provided for @changePasswordButton.
  ///
  /// In en, this message translates to:
  /// **'CHANGE PASSWORD'**
  String get changePasswordButton;

  /// No description provided for @enterConfirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter and confirm your new password'**
  String get enterConfirmNewPassword;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back,'**
  String get welcomeBack;

  /// No description provided for @regionSelectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select a region to view available auctions'**
  String get regionSelectSubtitle;

  /// No description provided for @chooseRegion.
  ///
  /// In en, this message translates to:
  /// **'Choose Region'**
  String get chooseRegion;

  /// No description provided for @canChangeRegion.
  ///
  /// In en, this message translates to:
  /// **'You can change region anytime from the Home screen'**
  String get canChangeRegion;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'DASHBOARD'**
  String get dashboard;

  /// No description provided for @welcomeUser.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}'**
  String welcomeUser(String name);

  /// No description provided for @activeAuctions.
  ///
  /// In en, this message translates to:
  /// **'Active Auctions'**
  String get activeAuctions;

  /// No description provided for @searchAuctions.
  ///
  /// In en, this message translates to:
  /// **'Search auctions...'**
  String get searchAuctions;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @cars.
  ///
  /// In en, this message translates to:
  /// **'Cars'**
  String get cars;

  /// No description provided for @motorcycles.
  ///
  /// In en, this message translates to:
  /// **'Motorcycles'**
  String get motorcycles;

  /// No description provided for @bicycles.
  ///
  /// In en, this message translates to:
  /// **'Bicycles'**
  String get bicycles;

  /// No description provided for @noAuctionsInRegion.
  ///
  /// In en, this message translates to:
  /// **'No active auctions in the {region} Region.\nCheck back later.'**
  String noAuctionsInRegion(String region);

  /// No description provided for @auctionDetails.
  ///
  /// In en, this message translates to:
  /// **'Auction Details'**
  String get auctionDetails;

  /// No description provided for @minimumPrice.
  ///
  /// In en, this message translates to:
  /// **'MINIMUM PRICE'**
  String get minimumPrice;

  /// No description provided for @totalBidders.
  ///
  /// In en, this message translates to:
  /// **'TOTAL\nBIDDERS'**
  String get totalBidders;

  /// No description provided for @currentHighestBid.
  ///
  /// In en, this message translates to:
  /// **'Current\nHighest Bid'**
  String get currentHighestBid;

  /// No description provided for @auctionEnded.
  ///
  /// In en, this message translates to:
  /// **'Auction Ended'**
  String get auctionEnded;

  /// No description provided for @countdownRemaining.
  ///
  /// In en, this message translates to:
  /// **'{countdown} Remaining'**
  String countdownRemaining(String countdown);

  /// No description provided for @updateYourBid.
  ///
  /// In en, this message translates to:
  /// **'UPDATE YOUR BID'**
  String get updateYourBid;

  /// No description provided for @placeYourBid.
  ///
  /// In en, this message translates to:
  /// **'PLACE YOUR BID'**
  String get placeYourBid;

  /// No description provided for @updateBidButton.
  ///
  /// In en, this message translates to:
  /// **'UPDATE BID'**
  String get updateBidButton;

  /// No description provided for @placeBidButton.
  ///
  /// In en, this message translates to:
  /// **'PLACE BID'**
  String get placeBidButton;

  /// No description provided for @auctionHasEnded.
  ///
  /// In en, this message translates to:
  /// **'This auction has ended'**
  String get auctionHasEnded;

  /// No description provided for @biddingAgreement.
  ///
  /// In en, this message translates to:
  /// **'By bidding you agree to the RNP Auction Terms'**
  String get biddingAgreement;

  /// No description provided for @vehicleSpecs.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Specifications'**
  String get vehicleSpecs;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @condition.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get condition;

  /// No description provided for @plateNumber.
  ///
  /// In en, this message translates to:
  /// **'Plate Number'**
  String get plateNumber;

  /// No description provided for @postedBy.
  ///
  /// In en, this message translates to:
  /// **'Posted By'**
  String get postedBy;

  /// No description provided for @failedToLoadAuction.
  ///
  /// In en, this message translates to:
  /// **'Failed to load auction: {error}'**
  String failedToLoadAuction(String error);

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// No description provided for @loadingAccount.
  ///
  /// In en, this message translates to:
  /// **'Loading your account, please wait...'**
  String get loadingAccount;

  /// No description provided for @pleaseLogin.
  ///
  /// In en, this message translates to:
  /// **'Please log in to place a bid'**
  String get pleaseLogin;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'START DATE'**
  String get startDate;

  /// No description provided for @endDate.
  ///
  /// In en, this message translates to:
  /// **'END DATE'**
  String get endDate;

  /// No description provided for @conditionLabel.
  ///
  /// In en, this message translates to:
  /// **'CONDITION'**
  String get conditionLabel;

  /// No description provided for @plateNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'PLATE NUMBER'**
  String get plateNumberLabel;

  /// No description provided for @updateBidTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Your Bid'**
  String get updateBidTitle;

  /// No description provided for @placeBidTitle.
  ///
  /// In en, this message translates to:
  /// **'Place Your Bid'**
  String get placeBidTitle;

  /// No description provided for @yourCurrentBid.
  ///
  /// In en, this message translates to:
  /// **'Your Current Bid'**
  String get yourCurrentBid;

  /// No description provided for @yourBidAmount.
  ///
  /// In en, this message translates to:
  /// **'Your Bid Amount (RWF)'**
  String get yourBidAmount;

  /// No description provided for @region.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get region;

  /// No description provided for @myBids.
  ///
  /// In en, this message translates to:
  /// **'MY BIDS'**
  String get myBids;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'TOTAL'**
  String get total;

  /// No description provided for @winning.
  ///
  /// In en, this message translates to:
  /// **'WINNING'**
  String get winning;

  /// No description provided for @won.
  ///
  /// In en, this message translates to:
  /// **'WON'**
  String get won;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @lost.
  ///
  /// In en, this message translates to:
  /// **'Lost'**
  String get lost;

  /// No description provided for @noBidsYet.
  ///
  /// In en, this message translates to:
  /// **'No bids yet...'**
  String get noBidsYet;

  /// No description provided for @noFilterBids.
  ///
  /// In en, this message translates to:
  /// **'No {filter} bids.'**
  String noFilterBids(String filter);

  /// No description provided for @bidUpdated.
  ///
  /// In en, this message translates to:
  /// **'Bid Updated'**
  String get bidUpdated;

  /// No description provided for @bidPlaced.
  ///
  /// In en, this message translates to:
  /// **'Bid Placed'**
  String get bidPlaced;

  /// No description provided for @bidUpdatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Bid Updated!'**
  String get bidUpdatedTitle;

  /// No description provided for @bidPlacedTitle.
  ///
  /// In en, this message translates to:
  /// **'Bid Successfully Placed!'**
  String get bidPlacedTitle;

  /// No description provided for @bidUpdatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Your bid has been updated in the\nRwanda National Police ledger.'**
  String get bidUpdatedMessage;

  /// No description provided for @bidPlacedMessage.
  ///
  /// In en, this message translates to:
  /// **'Your bid has been submitted and registered to the\nRwanda National Police ledger.'**
  String get bidPlacedMessage;

  /// No description provided for @bidReference.
  ///
  /// In en, this message translates to:
  /// **'BID REFERENCE'**
  String get bidReference;

  /// No description provided for @itemDetails.
  ///
  /// In en, this message translates to:
  /// **'ITEM DETAILS'**
  String get itemDetails;

  /// No description provided for @yourBidAmount2.
  ///
  /// In en, this message translates to:
  /// **'YOUR BID AMOUNT'**
  String get yourBidAmount2;

  /// No description provided for @submittedOn.
  ///
  /// In en, this message translates to:
  /// **'Submitted On {date}'**
  String submittedOn(String date);

  /// No description provided for @currentStatus.
  ///
  /// In en, this message translates to:
  /// **'CURRENT STATUS'**
  String get currentStatus;

  /// No description provided for @currentlyWinning.
  ///
  /// In en, this message translates to:
  /// **'CURRENTLY WINNING'**
  String get currentlyWinning;

  /// No description provided for @bidRegistered.
  ///
  /// In en, this message translates to:
  /// **'BID REGISTERED'**
  String get bidRegistered;

  /// No description provided for @viewMyBids.
  ///
  /// In en, this message translates to:
  /// **'VIEW MY BIDS'**
  String get viewMyBids;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get backToHome;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @bids.
  ///
  /// In en, this message translates to:
  /// **'Bids'**
  String get bids;

  /// No description provided for @auctions.
  ///
  /// In en, this message translates to:
  /// **'Auctions'**
  String get auctions;

  /// No description provided for @results.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get results;

  /// No description provided for @noNotificationsYet.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotificationsYet;

  /// No description provided for @noFilterNotifications.
  ///
  /// In en, this message translates to:
  /// **'No {filter} notifications'**
  String noFilterNotifications(String filter);

  /// No description provided for @notifyAboutBids.
  ///
  /// In en, this message translates to:
  /// **'We\'ll notify you about bids, auction results, and more.'**
  String get notifyAboutBids;

  /// No description provided for @winningStreak.
  ///
  /// In en, this message translates to:
  /// **'Winning Streak?'**
  String get winningStreak;

  /// No description provided for @keepBidding.
  ///
  /// In en, this message translates to:
  /// **'Keep bidding to stay on top.'**
  String get keepBidding;

  /// No description provided for @viewAuctions.
  ///
  /// In en, this message translates to:
  /// **'VIEW AUCTIONS'**
  String get viewAuctions;

  /// No description provided for @viewAuction.
  ///
  /// In en, this message translates to:
  /// **'View Auction'**
  String get viewAuction;

  /// No description provided for @markAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as Read'**
  String get markAsRead;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfile;

  /// No description provided for @activeClient.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE CLIENT'**
  String get activeClient;

  /// No description provided for @accountInformation.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT INFORMATION'**
  String get accountInformation;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'PREFERENCES'**
  String get preferences;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @kinyarwanda.
  ///
  /// In en, this message translates to:
  /// **'Kinyarwanda'**
  String get kinyarwanda;

  /// No description provided for @auctionRegion.
  ///
  /// In en, this message translates to:
  /// **'Auction Region'**
  String get auctionRegion;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'SECURITY'**
  String get security;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'SUPPORT'**
  String get support;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @helpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get helpCenter;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About E-Cyamunara'**
  String get aboutApp;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'LOGOUT'**
  String get logout;

  /// No description provided for @logoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get logoutConfirmMessage;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @totalBids.
  ///
  /// In en, this message translates to:
  /// **'TOTAL BIDS'**
  String get totalBids;

  /// No description provided for @joined.
  ///
  /// In en, this message translates to:
  /// **'JOINED'**
  String get joined;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'SAVE CHANGES'**
  String get saveChanges;

  /// No description provided for @passwordChangedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get passwordChangedSuccess;

  /// No description provided for @profileUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profileUpdatedSuccess;

  /// No description provided for @profileUpdatedPhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'Profile updated. Photo upload failed.'**
  String get profileUpdatedPhotoFailed;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @feedbackNav.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedbackNav;

  /// No description provided for @myBidsNav.
  ///
  /// In en, this message translates to:
  /// **'My Bids'**
  String get myBidsNav;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @endsSoon.
  ///
  /// In en, this message translates to:
  /// **'ENDS SOON'**
  String get endsSoon;

  /// No description provided for @timeLeft.
  ///
  /// In en, this message translates to:
  /// **'TIME LEFT'**
  String get timeLeft;

  /// No description provided for @currentBid.
  ///
  /// In en, this message translates to:
  /// **'Current Bid'**
  String get currentBid;

  /// No description provided for @bidNow.
  ///
  /// In en, this message translates to:
  /// **'BID NOW'**
  String get bidNow;

  /// No description provided for @yourBidLabel.
  ///
  /// In en, this message translates to:
  /// **'Your Bid:'**
  String get yourBidLabel;

  /// No description provided for @updateBid.
  ///
  /// In en, this message translates to:
  /// **'Update Bid'**
  String get updateBid;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetails;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @timeExpired.
  ///
  /// In en, this message translates to:
  /// **'Time expired'**
  String get timeExpired;

  /// No description provided for @daysHoursRemaining.
  ///
  /// In en, this message translates to:
  /// **'{d}d {h}h remaining'**
  String daysHoursRemaining(int d, int h);

  /// No description provided for @hoursMinutesRemaining.
  ///
  /// In en, this message translates to:
  /// **'{h}h {m}m remaining'**
  String hoursMinutesRemaining(int h, int m);

  /// No description provided for @minutesRemaining.
  ///
  /// In en, this message translates to:
  /// **'{m}m remaining'**
  String minutesRemaining(int m);

  /// No description provided for @wonBadge.
  ///
  /// In en, this message translates to:
  /// **'Won'**
  String get wonBadge;

  /// No description provided for @lostBadge.
  ///
  /// In en, this message translates to:
  /// **'Lost'**
  String get lostBadge;

  /// No description provided for @winningBadge.
  ///
  /// In en, this message translates to:
  /// **'Winning'**
  String get winningBadge;

  /// No description provided for @outbidBadge.
  ///
  /// In en, this message translates to:
  /// **'Outbid'**
  String get outbidBadge;

  /// No description provided for @highestBadge.
  ///
  /// In en, this message translates to:
  /// **'HIGHEST'**
  String get highestBadge;

  /// No description provided for @noAuctionsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No auctions available'**
  String get noAuctionsAvailable;

  /// No description provided for @adminDashboard.
  ///
  /// In en, this message translates to:
  /// **'ADMIN DASHBOARD'**
  String get adminDashboard;

  /// No description provided for @activeAuctionsCount.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE AUCTIONS'**
  String get activeAuctionsCount;

  /// No description provided for @bidsToday.
  ///
  /// In en, this message translates to:
  /// **'BIDS TODAY'**
  String get bidsToday;

  /// No description provided for @closedAuctions.
  ///
  /// In en, this message translates to:
  /// **'CLOSED AUCTIONS'**
  String get closedAuctions;

  /// No description provided for @registeredClients.
  ///
  /// In en, this message translates to:
  /// **'REGISTERED\nCLIENTS'**
  String get registeredClients;

  /// No description provided for @recentAuctions.
  ///
  /// In en, this message translates to:
  /// **'Recent Auctions'**
  String get recentAuctions;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get seeAll;

  /// No description provided for @failedToLoadStats.
  ///
  /// In en, this message translates to:
  /// **'Failed to load stats'**
  String get failedToLoadStats;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @failedToLoadRecentAuctions.
  ///
  /// In en, this message translates to:
  /// **'Failed to load recent auctions'**
  String get failedToLoadRecentAuctions;

  /// No description provided for @clientFeedback.
  ///
  /// In en, this message translates to:
  /// **'Client Feedback'**
  String get clientFeedback;

  /// No description provided for @viewFeedbackDesc.
  ///
  /// In en, this message translates to:
  /// **'View feedback submitted by clients in your region'**
  String get viewFeedbackDesc;

  /// No description provided for @regionAdmin.
  ///
  /// In en, this message translates to:
  /// **'Region Admin'**
  String get regionAdmin;

  /// No description provided for @regionAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'{region} Region Admin'**
  String regionAdminTitle(String region);

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'ADMIN'**
  String get admin;

  /// No description provided for @homeNav.
  ///
  /// In en, this message translates to:
  /// **'HOME'**
  String get homeNav;

  /// No description provided for @auctionsNav.
  ///
  /// In en, this message translates to:
  /// **'AUCTIONS'**
  String get auctionsNav;

  /// No description provided for @clientsNav.
  ///
  /// In en, this message translates to:
  /// **'CLIENTS'**
  String get clientsNav;

  /// No description provided for @reportsNav.
  ///
  /// In en, this message translates to:
  /// **'REPORTS'**
  String get reportsNav;

  /// No description provided for @profileNav.
  ///
  /// In en, this message translates to:
  /// **'PROFILE'**
  String get profileNav;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get live;

  /// No description provided for @ended.
  ///
  /// In en, this message translates to:
  /// **'ENDED'**
  String get ended;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'DRAFT'**
  String get draft;

  /// No description provided for @winningBid.
  ///
  /// In en, this message translates to:
  /// **'WINNING BID'**
  String get winningBid;

  /// No description provided for @currentBidAdmin.
  ///
  /// In en, this message translates to:
  /// **'CURRENT BID'**
  String get currentBidAdmin;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @allowed.
  ///
  /// In en, this message translates to:
  /// **'ALLOWED'**
  String get allowed;

  /// No description provided for @denied.
  ///
  /// In en, this message translates to:
  /// **'DENIED'**
  String get denied;

  /// No description provided for @suspended.
  ///
  /// In en, this message translates to:
  /// **'SUSPENDED'**
  String get suspended;

  /// No description provided for @winsCount.
  ///
  /// In en, this message translates to:
  /// **'Wins'**
  String get winsCount;

  /// No description provided for @bidsCount.
  ///
  /// In en, this message translates to:
  /// **'Bids'**
  String get bidsCount;

  /// No description provided for @viewReport.
  ///
  /// In en, this message translates to:
  /// **'View Report'**
  String get viewReport;

  /// No description provided for @closeAuctionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close Auction'**
  String get closeAuctionTooltip;

  /// No description provided for @postNewAuction.
  ///
  /// In en, this message translates to:
  /// **'POST NEW AUCTION'**
  String get postNewAuction;

  /// No description provided for @editAuction.
  ///
  /// In en, this message translates to:
  /// **'EDIT AUCTION'**
  String get editAuction;

  /// No description provided for @sovereignLedger.
  ///
  /// In en, this message translates to:
  /// **'SOVEREIGN LEDGER'**
  String get sovereignLedger;

  /// No description provided for @registerAssets.
  ///
  /// In en, this message translates to:
  /// **'Register Assets'**
  String get registerAssets;

  /// No description provided for @formalDocumentation.
  ///
  /// In en, this message translates to:
  /// **'Fill in the formal documentation for this asset.'**
  String get formalDocumentation;

  /// No description provided for @itemInformation.
  ///
  /// In en, this message translates to:
  /// **'ITEM INFORMATION'**
  String get itemInformation;

  /// No description provided for @assetName.
  ///
  /// In en, this message translates to:
  /// **'ASSET NAME'**
  String get assetName;

  /// No description provided for @categoryLabel.
  ///
  /// In en, this message translates to:
  /// **'CATEGORY'**
  String get categoryLabel;

  /// No description provided for @plateNumberField.
  ///
  /// In en, this message translates to:
  /// **'PLATE NUMBER'**
  String get plateNumberField;

  /// No description provided for @conditionField.
  ///
  /// In en, this message translates to:
  /// **'CONDITION'**
  String get conditionField;

  /// No description provided for @itemPhotos.
  ///
  /// In en, this message translates to:
  /// **'ITEM PHOTOS'**
  String get itemPhotos;

  /// No description provided for @photosCannotChange.
  ///
  /// In en, this message translates to:
  /// **'Photos cannot be changed after posting.'**
  String get photosCannotChange;

  /// No description provided for @photosSelected.
  ///
  /// In en, this message translates to:
  /// **'{count}/5 photos selected'**
  String photosSelected(int count);

  /// No description provided for @auctionDetailsSection.
  ///
  /// In en, this message translates to:
  /// **'AUCTION DETAILS'**
  String get auctionDetailsSection;

  /// No description provided for @startingPrice.
  ///
  /// In en, this message translates to:
  /// **'STARTING PRICE (RWF)'**
  String get startingPrice;

  /// No description provided for @storageRegion.
  ///
  /// In en, this message translates to:
  /// **'STORAGE REGION'**
  String get storageRegion;

  /// No description provided for @descriptionField.
  ///
  /// In en, this message translates to:
  /// **'DESCRIPTION'**
  String get descriptionField;

  /// No description provided for @postAuction.
  ///
  /// In en, this message translates to:
  /// **'POST AUCTION'**
  String get postAuction;

  /// No description provided for @saveAsDraft.
  ///
  /// In en, this message translates to:
  /// **'SAVE AS DRAFT'**
  String get saveAsDraft;

  /// No description provided for @saveChangesButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE CHANGES'**
  String get saveChangesButton;

  /// No description provided for @auctionUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Auction updated successfully!'**
  String get auctionUpdatedSuccess;

  /// No description provided for @auctionSavedDraft.
  ///
  /// In en, this message translates to:
  /// **'Auction saved as draft'**
  String get auctionSavedDraft;

  /// No description provided for @auctionPostedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Auction posted successfully!'**
  String get auctionPostedSuccess;

  /// No description provided for @selectDatesError.
  ///
  /// In en, this message translates to:
  /// **'Please select start and end dates'**
  String get selectDatesError;

  /// No description provided for @endDateAfterStartError.
  ///
  /// In en, this message translates to:
  /// **'End date must be after start date'**
  String get endDateAfterStartError;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'UPLOAD'**
  String get upload;

  /// No description provided for @addPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add Photos'**
  String get addPhotos;

  /// No description provided for @tapToAddPhotos.
  ///
  /// In en, this message translates to:
  /// **'Tap to add photos'**
  String get tapToAddPhotos;

  /// No description provided for @manageAuctions.
  ///
  /// In en, this message translates to:
  /// **'Manage Auctions'**
  String get manageAuctions;

  /// No description provided for @searchAuctionLots.
  ///
  /// In en, this message translates to:
  /// **'Search auction lots, vehicles, or IDs...'**
  String get searchAuctionLots;

  /// No description provided for @deleteAuction.
  ///
  /// In en, this message translates to:
  /// **'Delete Auction'**
  String get deleteAuction;

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\" (LOT #{id})?\n\nThis will permanently remove the auction and all its photos. This action cannot be undone.'**
  String deleteConfirmMessage(String name, String id);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get delete;

  /// No description provided for @auctionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Auction deleted.'**
  String get auctionDeleted;

  /// No description provided for @failedToLoadAuctions.
  ///
  /// In en, this message translates to:
  /// **'Failed to load auctions'**
  String get failedToLoadAuctions;

  /// No description provided for @noAuctionsMatch.
  ///
  /// In en, this message translates to:
  /// **'No auctions match \"{query}\"'**
  String noAuctionsMatch(String query);

  /// No description provided for @noAuctionsYet.
  ///
  /// In en, this message translates to:
  /// **'No {filter} auctions yet.'**
  String noAuctionsYet(String filter);

  /// No description provided for @viewBids.
  ///
  /// In en, this message translates to:
  /// **'View Bids'**
  String get viewBids;

  /// No description provided for @closeAuctionScreen.
  ///
  /// In en, this message translates to:
  /// **'Close Auction'**
  String get closeAuctionScreen;

  /// No description provided for @bidDetails.
  ///
  /// In en, this message translates to:
  /// **'Bid Details'**
  String get bidDetails;

  /// No description provided for @noBidsForAuction.
  ///
  /// In en, this message translates to:
  /// **'No bids for this auction yet'**
  String get noBidsForAuction;

  /// No description provided for @clientManagement.
  ///
  /// In en, this message translates to:
  /// **'CLIENT MANAGEMENT'**
  String get clientManagement;

  /// No description provided for @searchClients.
  ///
  /// In en, this message translates to:
  /// **'Search by name, ID, or email...'**
  String get searchClients;

  /// No description provided for @failedToLoadClients.
  ///
  /// In en, this message translates to:
  /// **'Failed to load clients'**
  String get failedToLoadClients;

  /// No description provided for @suspendClient.
  ///
  /// In en, this message translates to:
  /// **'Suspend Client'**
  String get suspendClient;

  /// No description provided for @suspendClientMessage.
  ///
  /// In en, this message translates to:
  /// **'This will prevent the client from placing bids. You can reactivate them at any time.'**
  String get suspendClientMessage;

  /// No description provided for @suspend.
  ///
  /// In en, this message translates to:
  /// **'SUSPEND'**
  String get suspend;

  /// No description provided for @activateClient.
  ///
  /// In en, this message translates to:
  /// **'Activate Client'**
  String get activateClient;

  /// No description provided for @activateClientMessage.
  ///
  /// In en, this message translates to:
  /// **'This will restore full bidding access for this client.'**
  String get activateClientMessage;

  /// No description provided for @activate.
  ///
  /// In en, this message translates to:
  /// **'ACTIVATE'**
  String get activate;

  /// No description provided for @clientSuspended.
  ///
  /// In en, this message translates to:
  /// **'Client suspended.'**
  String get clientSuspended;

  /// No description provided for @clientActivated.
  ///
  /// In en, this message translates to:
  /// **'Client activated.'**
  String get clientActivated;

  /// No description provided for @noClientsMatch.
  ///
  /// In en, this message translates to:
  /// **'No clients match \"{query}\"'**
  String noClientsMatch(String query);

  /// No description provided for @noClientsYet.
  ///
  /// In en, this message translates to:
  /// **'No {filter} clients.'**
  String noClientsYet(String filter);

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'PHONE'**
  String get phone;

  /// No description provided for @districtLabel.
  ///
  /// In en, this message translates to:
  /// **'DISTRICT'**
  String get districtLabel;

  /// No description provided for @province.
  ///
  /// In en, this message translates to:
  /// **'PROVINCE'**
  String get province;

  /// No description provided for @lastLogin.
  ///
  /// In en, this message translates to:
  /// **'LAST LOGIN'**
  String get lastLogin;

  /// No description provided for @regionReports.
  ///
  /// In en, this message translates to:
  /// **'Region Reports'**
  String get regionReports;

  /// No description provided for @generateReport.
  ///
  /// In en, this message translates to:
  /// **'Generate Report'**
  String get generateReport;

  /// No description provided for @reportGenerated.
  ///
  /// In en, this message translates to:
  /// **'Report generated successfully'**
  String get reportGenerated;

  /// No description provided for @failedToGenerateReport.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate report'**
  String get failedToGenerateReport;

  /// No description provided for @downloadReport.
  ///
  /// In en, this message translates to:
  /// **'Download Report'**
  String get downloadReport;

  /// No description provided for @adminFeedback.
  ///
  /// In en, this message translates to:
  /// **'Client Feedback'**
  String get adminFeedback;

  /// No description provided for @noFeedbackYet.
  ///
  /// In en, this message translates to:
  /// **'No feedback submitted yet'**
  String get noFeedbackYet;

  /// No description provided for @feedbackFrom.
  ///
  /// In en, this message translates to:
  /// **'Feedback from {name}'**
  String feedbackFrom(String name);

  /// No description provided for @editRegionAdmin.
  ///
  /// In en, this message translates to:
  /// **'Edit Region Admin'**
  String get editRegionAdmin;

  /// No description provided for @addRegionAdmin.
  ///
  /// In en, this message translates to:
  /// **'Add Region Admin'**
  String get addRegionAdmin;

  /// No description provided for @adminInformation.
  ///
  /// In en, this message translates to:
  /// **'ADMIN INFORMATION'**
  String get adminInformation;

  /// No description provided for @temporaryPasswordNote.
  ///
  /// In en, this message translates to:
  /// **'A secure temporary password will be generated automatically.'**
  String get temporaryPasswordNote;

  /// No description provided for @regionAssignment.
  ///
  /// In en, this message translates to:
  /// **'REGION ASSIGNMENT'**
  String get regionAssignment;

  /// No description provided for @regionCannotChange.
  ///
  /// In en, this message translates to:
  /// **'Region cannot be changed after creation.'**
  String get regionCannotChange;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'PERMISSIONS'**
  String get permissions;

  /// No description provided for @postAuctionsPermission.
  ///
  /// In en, this message translates to:
  /// **'Post Auctions'**
  String get postAuctionsPermission;

  /// No description provided for @createNewLots.
  ///
  /// In en, this message translates to:
  /// **'Create new vehicle lots'**
  String get createNewLots;

  /// No description provided for @manageClientsPermission.
  ///
  /// In en, this message translates to:
  /// **'Manage Clients'**
  String get manageClientsPermission;

  /// No description provided for @reviewBidderDocs.
  ///
  /// In en, this message translates to:
  /// **'Review bidder documentation'**
  String get reviewBidderDocs;

  /// No description provided for @viewReportsPermission.
  ///
  /// In en, this message translates to:
  /// **'View Reports'**
  String get viewReportsPermission;

  /// No description provided for @accessRegionalStats.
  ///
  /// In en, this message translates to:
  /// **'Access regional statistics'**
  String get accessRegionalStats;

  /// No description provided for @closeAuctionsPermission.
  ///
  /// In en, this message translates to:
  /// **'Close Auctions'**
  String get closeAuctionsPermission;

  /// No description provided for @manuallyCloseAndAward.
  ///
  /// In en, this message translates to:
  /// **'Manually close and award'**
  String get manuallyCloseAndAward;

  /// No description provided for @adminCreated.
  ///
  /// In en, this message translates to:
  /// **'Admin Created'**
  String get adminCreated;

  /// No description provided for @adminCreatedFor.
  ///
  /// In en, this message translates to:
  /// **'{name} has been created for the {region} Region.'**
  String adminCreatedFor(String name, String region);

  /// No description provided for @temporaryPassword.
  ///
  /// In en, this message translates to:
  /// **'Temporary Password'**
  String get temporaryPassword;

  /// No description provided for @savePasswordWarning.
  ///
  /// In en, this message translates to:
  /// **'Save this password — it cannot be retrieved after closing this dialog.'**
  String get savePasswordWarning;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @copyPassword.
  ///
  /// In en, this message translates to:
  /// **'Copy password'**
  String get copyPassword;

  /// No description provided for @passwordCopied.
  ///
  /// In en, this message translates to:
  /// **'Password copied to clipboard'**
  String get passwordCopied;

  /// No description provided for @pleaseSelectRegion.
  ///
  /// In en, this message translates to:
  /// **'Please select a region'**
  String get pleaseSelectRegion;

  /// No description provided for @creationFailed.
  ///
  /// In en, this message translates to:
  /// **'Creation failed: {error}'**
  String creationFailed(String error);

  /// No description provided for @adminUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Admin updated successfully'**
  String get adminUpdatedSuccess;

  /// No description provided for @failedToUpdateAdmin.
  ///
  /// In en, this message translates to:
  /// **'Failed to update admin: {error}'**
  String failedToUpdateAdmin(String error);

  /// No description provided for @superAdminDashboard.
  ///
  /// In en, this message translates to:
  /// **'SUPER ADMIN'**
  String get superAdminDashboard;

  /// No description provided for @commissioner.
  ///
  /// In en, this message translates to:
  /// **'Commissioner'**
  String get commissioner;

  /// No description provided for @superAdministrator.
  ///
  /// In en, this message translates to:
  /// **'Super Administrator'**
  String get superAdministrator;

  /// No description provided for @nationalRevenue.
  ///
  /// In en, this message translates to:
  /// **'NATIONAL REVENUE'**
  String get nationalRevenue;

  /// No description provided for @totalCollectedAllTime.
  ///
  /// In en, this message translates to:
  /// **'Total Collected — All Time'**
  String get totalCollectedAllTime;

  /// No description provided for @closedAuctionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} closed auctions'**
  String closedAuctionsCount(int count);

  /// No description provided for @regionsOverview.
  ///
  /// In en, this message translates to:
  /// **'Regions Overview'**
  String get regionsOverview;

  /// No description provided for @adminActivity.
  ///
  /// In en, this message translates to:
  /// **'Admin Activity'**
  String get adminActivity;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @appSettings.
  ///
  /// In en, this message translates to:
  /// **'App Settings'**
  String get appSettings;

  /// No description provided for @nationalReports.
  ///
  /// In en, this message translates to:
  /// **'National Reports'**
  String get nationalReports;

  /// No description provided for @totalAuctions.
  ///
  /// In en, this message translates to:
  /// **'TOTAL AUCTIONS'**
  String get totalAuctions;

  /// No description provided for @totalBidsLabel.
  ///
  /// In en, this message translates to:
  /// **'TOTAL BIDS'**
  String get totalBidsLabel;

  /// No description provided for @clients.
  ///
  /// In en, this message translates to:
  /// **'CLIENTS'**
  String get clients;

  /// No description provided for @regionAdmins.
  ///
  /// In en, this message translates to:
  /// **'REGION ADMINS'**
  String get regionAdmins;

  /// No description provided for @noRegionAdmins.
  ///
  /// In en, this message translates to:
  /// **'No region admins yet.\nTap + to add the first admin.'**
  String get noRegionAdmins;

  /// No description provided for @noAdminActivity.
  ///
  /// In en, this message translates to:
  /// **'No admin activity yet'**
  String get noAdminActivity;

  /// No description provided for @loadingRegions.
  ///
  /// In en, this message translates to:
  /// **'Loading regions…'**
  String get loadingRegions;

  /// No description provided for @auctionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} auctions'**
  String auctionsCount(int count);

  /// No description provided for @regionLabel.
  ///
  /// In en, this message translates to:
  /// **'{region} Region'**
  String regionLabel(String region);

  /// No description provided for @manageAdmins.
  ///
  /// In en, this message translates to:
  /// **'Manage Admins'**
  String get manageAdmins;

  /// No description provided for @searchAdmins.
  ///
  /// In en, this message translates to:
  /// **'Search admins...'**
  String get searchAdmins;

  /// No description provided for @noAdminsMatch.
  ///
  /// In en, this message translates to:
  /// **'No admins match \"{query}\"'**
  String noAdminsMatch(String query);

  /// No description provided for @noAdminsYet.
  ///
  /// In en, this message translates to:
  /// **'No admins yet'**
  String get noAdminsYet;

  /// No description provided for @superAdminNav1.
  ///
  /// In en, this message translates to:
  /// **'DASHBOARD'**
  String get superAdminNav1;

  /// No description provided for @superAdminNav2.
  ///
  /// In en, this message translates to:
  /// **'ADMINS'**
  String get superAdminNav2;

  /// No description provided for @superAdminNav3.
  ///
  /// In en, this message translates to:
  /// **'REPORTS'**
  String get superAdminNav3;

  /// No description provided for @superAdminNav4.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS'**
  String get superAdminNav4;

  /// No description provided for @superAdminNav5.
  ///
  /// In en, this message translates to:
  /// **'PROFILE'**
  String get superAdminNav5;

  /// No description provided for @feedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedbackTitle;

  /// No description provided for @feedbackHeaderTitle.
  ///
  /// In en, this message translates to:
  /// **'E-CYAMUNARA Feedback'**
  String get feedbackHeaderTitle;

  /// No description provided for @auctionFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'E-CYAMUNARA Auction\nFeedback'**
  String get auctionFeedbackTitle;

  /// No description provided for @helpImprove.
  ///
  /// In en, this message translates to:
  /// **'Help us improve our platform'**
  String get helpImprove;

  /// No description provided for @helpImproveService.
  ///
  /// In en, this message translates to:
  /// **'Help us improve our service'**
  String get helpImproveService;

  /// No description provided for @rateExperience.
  ///
  /// In en, this message translates to:
  /// **'Rate Your Experience'**
  String get rateExperience;

  /// No description provided for @howSatisfied.
  ///
  /// In en, this message translates to:
  /// **'How satisfied are you with our platform?'**
  String get howSatisfied;

  /// No description provided for @howSatisfiedService.
  ///
  /// In en, this message translates to:
  /// **'How satisfied are you with our service?'**
  String get howSatisfiedService;

  /// No description provided for @whatWentWell.
  ///
  /// In en, this message translates to:
  /// **'What went well?'**
  String get whatWentWell;

  /// No description provided for @additionalComments.
  ///
  /// In en, this message translates to:
  /// **'Additional Comments'**
  String get additionalComments;

  /// No description provided for @shareExperience.
  ///
  /// In en, this message translates to:
  /// **'Share your experience...'**
  String get shareExperience;

  /// No description provided for @wouldRecommend.
  ///
  /// In en, this message translates to:
  /// **'Would you recommend E-CYAMUNARA?'**
  String get wouldRecommend;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @submitFeedback.
  ///
  /// In en, this message translates to:
  /// **'SUBMIT FEEDBACK'**
  String get submitFeedback;

  /// No description provided for @thankYouFeedback.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your feedback!'**
  String get thankYouFeedback;

  /// No description provided for @failedToSubmit.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit: {error}'**
  String failedToSubmit(String error);

  /// No description provided for @thankYouRnp.
  ///
  /// In en, this message translates to:
  /// **'Thank you for helping Rwanda National Police improve'**
  String get thankYouRnp;

  /// No description provided for @indicateRecommend.
  ///
  /// In en, this message translates to:
  /// **'Please indicate if you would recommend'**
  String get indicateRecommend;

  /// No description provided for @auctionItem.
  ///
  /// In en, this message translates to:
  /// **'AUCTION ITEM'**
  String get auctionItem;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'DATE'**
  String get date;

  /// No description provided for @tagEasyToUse.
  ///
  /// In en, this message translates to:
  /// **'Easy to Use'**
  String get tagEasyToUse;

  /// No description provided for @tagFastProcess.
  ///
  /// In en, this message translates to:
  /// **'Fast Process'**
  String get tagFastProcess;

  /// No description provided for @tagTransparency.
  ///
  /// In en, this message translates to:
  /// **'Transparency'**
  String get tagTransparency;

  /// No description provided for @tagCommunication.
  ///
  /// In en, this message translates to:
  /// **'Communication'**
  String get tagCommunication;

  /// No description provided for @tagPaymentFlow.
  ///
  /// In en, this message translates to:
  /// **'Payment Flow'**
  String get tagPaymentFlow;

  /// No description provided for @tagDocumentation.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get tagDocumentation;

  /// No description provided for @ratingPoor.
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get ratingPoor;

  /// No description provided for @ratingFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get ratingFair;

  /// No description provided for @ratingGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get ratingGood;

  /// No description provided for @ratingVeryGood.
  ///
  /// In en, this message translates to:
  /// **'Very Good'**
  String get ratingVeryGood;

  /// No description provided for @ratingExcellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get ratingExcellent;

  /// No description provided for @validatorPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get validatorPhoneRequired;

  /// No description provided for @validatorPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Rwanda phone number (e.g. 078XXXXXXX)'**
  String get validatorPhoneInvalid;

  /// No description provided for @validatorNationalIdRequired.
  ///
  /// In en, this message translates to:
  /// **'National ID is required'**
  String get validatorNationalIdRequired;

  /// No description provided for @validatorNationalIdLength.
  ///
  /// In en, this message translates to:
  /// **'National ID must be exactly 16 digits'**
  String get validatorNationalIdLength;

  /// No description provided for @validatorNationalIdDigitsOnly.
  ///
  /// In en, this message translates to:
  /// **'National ID must contain digits only'**
  String get validatorNationalIdDigitsOnly;

  /// No description provided for @validatorPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get validatorPasswordRequired;

  /// No description provided for @validatorPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get validatorPasswordTooShort;

  /// No description provided for @validatorPasswordUppercase.
  ///
  /// In en, this message translates to:
  /// **'Add at least one uppercase letter'**
  String get validatorPasswordUppercase;

  /// No description provided for @validatorPasswordNumber.
  ///
  /// In en, this message translates to:
  /// **'Add at least one number'**
  String get validatorPasswordNumber;

  /// No description provided for @validatorPasswordSpecial.
  ///
  /// In en, this message translates to:
  /// **'Add at least one special character (!@#\$%^&*)'**
  String get validatorPasswordSpecial;

  /// No description provided for @validatorConfirmRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get validatorConfirmRequired;

  /// No description provided for @validatorPasswordsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get validatorPasswordsNoMatch;

  /// No description provided for @validatorFullNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Full name is required'**
  String get validatorFullNameRequired;

  /// No description provided for @validatorNameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Name is too short (minimum 3 characters)'**
  String get validatorNameTooShort;

  /// No description provided for @validatorBidRequired.
  ///
  /// In en, this message translates to:
  /// **'Bid amount is required'**
  String get validatorBidRequired;

  /// No description provided for @validatorBidInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get validatorBidInvalid;

  /// No description provided for @validatorBidZero.
  ///
  /// In en, this message translates to:
  /// **'Bid must be greater than zero'**
  String get validatorBidZero;

  /// No description provided for @validatorBidTooLow.
  ///
  /// In en, this message translates to:
  /// **'Bid must be higher than RWF {minimum}'**
  String validatorBidTooLow(String minimum);

  /// No description provided for @validatorDescriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Description is required'**
  String get validatorDescriptionRequired;

  /// No description provided for @validatorDescriptionTooShort.
  ///
  /// In en, this message translates to:
  /// **'Description must be at least 20 characters'**
  String get validatorDescriptionTooShort;

  /// No description provided for @validatorCommentTooLong.
  ///
  /// In en, this message translates to:
  /// **'Comment must not exceed 250 characters'**
  String get validatorCommentTooLong;

  /// No description provided for @validatorEndDateRequired.
  ///
  /// In en, this message translates to:
  /// **'End date is required'**
  String get validatorEndDateRequired;

  /// No description provided for @validatorEndDateBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'End date must be after start date'**
  String get validatorEndDateBeforeStart;

  /// No description provided for @validatorEndDatePast.
  ///
  /// In en, this message translates to:
  /// **'End date must be in the future'**
  String get validatorEndDatePast;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @superAdminBadge.
  ///
  /// In en, this message translates to:
  /// **'SUPER ADMIN'**
  String get superAdminBadge;

  /// No description provided for @regionAdminBadge.
  ///
  /// In en, this message translates to:
  /// **'REGION ADMIN'**
  String get regionAdminBadge;

  /// No description provided for @pendingBadge.
  ///
  /// In en, this message translates to:
  /// **'PENDING'**
  String get pendingBadge;

  /// No description provided for @activeBadge.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get activeBadge;

  /// No description provided for @offBadge.
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get offBadge;

  /// No description provided for @adminProfile.
  ///
  /// In en, this message translates to:
  /// **'Admin Profile'**
  String get adminProfile;

  /// No description provided for @postedStat.
  ///
  /// In en, this message translates to:
  /// **'POSTED'**
  String get postedStat;

  /// No description provided for @closedStat.
  ///
  /// In en, this message translates to:
  /// **'CLOSED'**
  String get closedStat;

  /// No description provided for @statusStat.
  ///
  /// In en, this message translates to:
  /// **'STATUS'**
  String get statusStat;

  /// No description provided for @roleLabel.
  ///
  /// In en, this message translates to:
  /// **'ROLE'**
  String get roleLabel;

  /// No description provided for @accountStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT STATUS'**
  String get accountStatusLabel;

  /// No description provided for @memberSince.
  ///
  /// In en, this message translates to:
  /// **'MEMBER SINCE'**
  String get memberSince;

  /// No description provided for @profileLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh profile. Showing last known data.'**
  String get profileLoadError;

  /// No description provided for @neverRecorded.
  ///
  /// In en, this message translates to:
  /// **'Never recorded'**
  String get neverRecorded;

  /// No description provided for @fullNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Full name cannot be empty'**
  String get fullNameEmpty;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String updateFailed(String error);

  /// No description provided for @passwordChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to change password: {error}'**
  String passwordChangeFailed(String error);

  /// No description provided for @updatePasswordDesc.
  ///
  /// In en, this message translates to:
  /// **'Update your account password'**
  String get updatePasswordDesc;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @failedToLoadAdmins.
  ///
  /// In en, this message translates to:
  /// **'Failed to load admins'**
  String get failedToLoadAdmins;

  /// No description provided for @tapToViewDetails.
  ///
  /// In en, this message translates to:
  /// **'Tap to view details'**
  String get tapToViewDetails;

  /// No description provided for @notOnRecord.
  ///
  /// In en, this message translates to:
  /// **'Not on record'**
  String get notOnRecord;

  /// No description provided for @addNewAdmin.
  ///
  /// In en, this message translates to:
  /// **'Add new admin'**
  String get addNewAdmin;

  /// No description provided for @suspendAdmin.
  ///
  /// In en, this message translates to:
  /// **'Suspend Admin'**
  String get suspendAdmin;

  /// No description provided for @suspendAdminMessage.
  ///
  /// In en, this message translates to:
  /// **'Suspend {name} ({region})?\n\nThey will be immediately signed out and unable to log in until re-activated.'**
  String suspendAdminMessage(String name, String region);

  /// No description provided for @activateAdmin.
  ///
  /// In en, this message translates to:
  /// **'Activate Admin'**
  String get activateAdmin;

  /// No description provided for @activateAdminMessage.
  ///
  /// In en, this message translates to:
  /// **'Re-activate {name} ({region})?\n\nThey will be able to log in immediately.'**
  String activateAdminMessage(String name, String region);

  /// No description provided for @adminSuspendedMsg.
  ///
  /// In en, this message translates to:
  /// **'{name} suspended'**
  String adminSuspendedMsg(String name);

  /// No description provided for @adminActivatedMsg.
  ///
  /// In en, this message translates to:
  /// **'{name} activated'**
  String adminActivatedMsg(String name);

  /// No description provided for @sessionExpiredError.
  ///
  /// In en, this message translates to:
  /// **'Session expired — please log in again'**
  String get sessionExpiredError;

  /// No description provided for @createAdmin.
  ///
  /// In en, this message translates to:
  /// **'CREATE ADMIN'**
  String get createAdmin;

  /// No description provided for @fiscalPerformance.
  ///
  /// In en, this message translates to:
  /// **'FISCAL PERFORMANCE'**
  String get fiscalPerformance;

  /// No description provided for @nationwideLedger.
  ///
  /// In en, this message translates to:
  /// **'Nationwide Ledger'**
  String get nationwideLedger;

  /// No description provided for @totalRevenue.
  ///
  /// In en, this message translates to:
  /// **'TOTAL REVENUE'**
  String get totalRevenue;

  /// No description provided for @auctionsLabel.
  ///
  /// In en, this message translates to:
  /// **'AUCTIONS'**
  String get auctionsLabel;

  /// No description provided for @bidsLabel.
  ///
  /// In en, this message translates to:
  /// **'BIDS'**
  String get bidsLabel;

  /// No description provided for @performanceByRegion.
  ///
  /// In en, this message translates to:
  /// **'Performance by Region'**
  String get performanceByRegion;

  /// No description provided for @failedToLoadRegionData.
  ///
  /// In en, this message translates to:
  /// **'Failed to load region data'**
  String get failedToLoadRegionData;

  /// No description provided for @noAuctionDataForPeriod.
  ///
  /// In en, this message translates to:
  /// **'No auction data for this period'**
  String get noAuctionDataForPeriod;

  /// No description provided for @reportReady.
  ///
  /// In en, this message translates to:
  /// **'Report Ready'**
  String get reportReady;

  /// No description provided for @reportCopyLinkInstruction.
  ///
  /// In en, this message translates to:
  /// **'Copy the link below and open it in your browser:'**
  String get reportCopyLinkInstruction;

  /// No description provided for @reportLinkValidity.
  ///
  /// In en, this message translates to:
  /// **'Link is valid for 7 days.'**
  String get reportLinkValidity;

  /// No description provided for @copyUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get copyUrl;

  /// No description provided for @urlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied to clipboard'**
  String get urlCopied;

  /// No description provided for @reportReadyNoUrl.
  ///
  /// In en, this message translates to:
  /// **'Report generated but no download URL returned'**
  String get reportReadyNoUrl;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailed(String error);

  /// No description provided for @superAdminProfile.
  ///
  /// In en, this message translates to:
  /// **'Super Admin Profile'**
  String get superAdminProfile;

  /// No description provided for @adminsBadge.
  ///
  /// In en, this message translates to:
  /// **'ADMINS'**
  String get adminsBadge;

  /// No description provided for @regionsCount.
  ///
  /// In en, this message translates to:
  /// **'REGIONS'**
  String get regionsCount;

  /// No description provided for @systemAccess.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM ACCESS'**
  String get systemAccess;

  /// No description provided for @manageRegionAdminsPermission.
  ///
  /// In en, this message translates to:
  /// **'Manage Region Admins'**
  String get manageRegionAdminsPermission;

  /// No description provided for @viewAllRegionsPermission.
  ///
  /// In en, this message translates to:
  /// **'View All Regions'**
  String get viewAllRegionsPermission;

  /// No description provided for @systemConfigPermission.
  ///
  /// In en, this message translates to:
  /// **'System Configuration'**
  String get systemConfigPermission;

  /// No description provided for @auditLogsPermission.
  ///
  /// In en, this message translates to:
  /// **'Audit Logs'**
  String get auditLogsPermission;

  /// No description provided for @authorityLabel.
  ///
  /// In en, this message translates to:
  /// **'AUTHORITY'**
  String get authorityLabel;

  /// No description provided for @nationalLevelRnp.
  ///
  /// In en, this message translates to:
  /// **'National Level — RNP'**
  String get nationalLevelRnp;

  /// No description provided for @basicInformation.
  ///
  /// In en, this message translates to:
  /// **'BASIC INFORMATION'**
  String get basicInformation;

  /// No description provided for @technicalSpecs.
  ///
  /// In en, this message translates to:
  /// **'TECHNICAL SPECIFICATIONS'**
  String get technicalSpecs;

  /// No description provided for @ownershipSection.
  ///
  /// In en, this message translates to:
  /// **'OWNERSHIP & HISTORY'**
  String get ownershipSection;

  /// No description provided for @mainCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'MAIN CATEGORY'**
  String get mainCategoryLabel;

  /// No description provided for @subCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'SUB-CATEGORY'**
  String get subCategoryLabel;

  /// No description provided for @brandLabel.
  ///
  /// In en, this message translates to:
  /// **'BRAND'**
  String get brandLabel;

  /// No description provided for @modelField.
  ///
  /// In en, this message translates to:
  /// **'MODEL'**
  String get modelField;

  /// No description provided for @manufacturingYearLabel.
  ///
  /// In en, this message translates to:
  /// **'MANUFACTURING YEAR'**
  String get manufacturingYearLabel;

  /// No description provided for @colorField.
  ///
  /// In en, this message translates to:
  /// **'COLOR'**
  String get colorField;

  /// No description provided for @mileageField.
  ///
  /// In en, this message translates to:
  /// **'MILEAGE (KM)'**
  String get mileageField;

  /// No description provided for @fuelTypeField.
  ///
  /// In en, this message translates to:
  /// **'FUEL TYPE'**
  String get fuelTypeField;

  /// No description provided for @transmissionField.
  ///
  /// In en, this message translates to:
  /// **'TRANSMISSION'**
  String get transmissionField;

  /// No description provided for @engineSizeField.
  ///
  /// In en, this message translates to:
  /// **'ENGINE SIZE (L)'**
  String get engineSizeField;

  /// No description provided for @engineCcField.
  ///
  /// In en, this message translates to:
  /// **'ENGINE CC'**
  String get engineCcField;

  /// No description provided for @drivetrainField.
  ///
  /// In en, this message translates to:
  /// **'DRIVETRAIN'**
  String get drivetrainField;

  /// No description provided for @seatingCapacityField.
  ///
  /// In en, this message translates to:
  /// **'SEATING CAPACITY'**
  String get seatingCapacityField;

  /// No description provided for @frameMaterialField.
  ///
  /// In en, this message translates to:
  /// **'FRAME MATERIAL'**
  String get frameMaterialField;

  /// No description provided for @gearCountField.
  ///
  /// In en, this message translates to:
  /// **'GEAR COUNT'**
  String get gearCountField;

  /// No description provided for @suspensionTypeField.
  ///
  /// In en, this message translates to:
  /// **'SUSPENSION TYPE'**
  String get suspensionTypeField;

  /// No description provided for @brakeTypeField.
  ///
  /// In en, this message translates to:
  /// **'BRAKE TYPE'**
  String get brakeTypeField;

  /// No description provided for @ownershipHistoryField.
  ///
  /// In en, this message translates to:
  /// **'OWNERSHIP HISTORY'**
  String get ownershipHistoryField;

  /// No description provided for @accidentHistoryField.
  ///
  /// In en, this message translates to:
  /// **'ACCIDENT HISTORY'**
  String get accidentHistoryField;

  /// No description provided for @insuranceStatusField.
  ///
  /// In en, this message translates to:
  /// **'INSURANCE STATUS'**
  String get insuranceStatusField;

  /// No description provided for @optionPetrol.
  ///
  /// In en, this message translates to:
  /// **'Petrol'**
  String get optionPetrol;

  /// No description provided for @optionDiesel.
  ///
  /// In en, this message translates to:
  /// **'Diesel'**
  String get optionDiesel;

  /// No description provided for @optionHybrid.
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get optionHybrid;

  /// No description provided for @optionElectric.
  ///
  /// In en, this message translates to:
  /// **'Electric'**
  String get optionElectric;

  /// No description provided for @optionAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get optionAutomatic;

  /// No description provided for @optionManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get optionManual;

  /// No description provided for @optionCvt.
  ///
  /// In en, this message translates to:
  /// **'CVT'**
  String get optionCvt;

  /// No description provided for @optionExcellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get optionExcellent;

  /// No description provided for @optionVeryGood.
  ///
  /// In en, this message translates to:
  /// **'Very Good'**
  String get optionVeryGood;

  /// No description provided for @optionGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get optionGood;

  /// No description provided for @optionFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get optionFair;

  /// No description provided for @optionPoor.
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get optionPoor;

  /// No description provided for @optionFirstOwner.
  ///
  /// In en, this message translates to:
  /// **'First Owner'**
  String get optionFirstOwner;

  /// No description provided for @optionSecondOwner.
  ///
  /// In en, this message translates to:
  /// **'Second Owner'**
  String get optionSecondOwner;

  /// No description provided for @optionThirdOwner.
  ///
  /// In en, this message translates to:
  /// **'Third Owner'**
  String get optionThirdOwner;

  /// No description provided for @optionFleetVehicle.
  ///
  /// In en, this message translates to:
  /// **'Fleet Vehicle'**
  String get optionFleetVehicle;

  /// No description provided for @optionInsured.
  ///
  /// In en, this message translates to:
  /// **'Insured'**
  String get optionInsured;

  /// No description provided for @optionExpiredInsurance.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get optionExpiredInsurance;

  /// No description provided for @optionNeverInsured.
  ///
  /// In en, this message translates to:
  /// **'Never Insured'**
  String get optionNeverInsured;

  /// No description provided for @optionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get optionUnknown;

  /// No description provided for @optionNoAccidents.
  ///
  /// In en, this message translates to:
  /// **'No Accidents'**
  String get optionNoAccidents;

  /// No description provided for @optionMinorDamage.
  ///
  /// In en, this message translates to:
  /// **'Minor Damage'**
  String get optionMinorDamage;

  /// No description provided for @optionMajorDamage.
  ///
  /// In en, this message translates to:
  /// **'Major Damage'**
  String get optionMajorDamage;

  /// No description provided for @validatorYearRange.
  ///
  /// In en, this message translates to:
  /// **'Year must be between 1900 and {year}'**
  String validatorYearRange(int year);

  /// No description provided for @validatorMileageNegative.
  ///
  /// In en, this message translates to:
  /// **'Mileage cannot be negative'**
  String get validatorMileageNegative;

  /// No description provided for @validatorEngineCcRequired.
  ///
  /// In en, this message translates to:
  /// **'Engine CC is required for motorcycles'**
  String get validatorEngineCcRequired;

  /// No description provided for @validatorEngineSizeRequired.
  ///
  /// In en, this message translates to:
  /// **'Engine size is required for vehicles'**
  String get validatorEngineSizeRequired;

  /// No description provided for @validatorTransmissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Transmission is required for vehicles'**
  String get validatorTransmissionRequired;

  /// No description provided for @validatorGearCountRequired.
  ///
  /// In en, this message translates to:
  /// **'Gear count is required for bicycles'**
  String get validatorGearCountRequired;

  /// No description provided for @validatorFuelTypeRequired.
  ///
  /// In en, this message translates to:
  /// **'Fuel type is required'**
  String get validatorFuelTypeRequired;

  /// No description provided for @validatorSubCategoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Sub-category is required'**
  String get validatorSubCategoryRequired;

  /// No description provided for @validatorBrandRequired.
  ///
  /// In en, this message translates to:
  /// **'Brand is required'**
  String get validatorBrandRequired;

  /// No description provided for @validatorModelRequired.
  ///
  /// In en, this message translates to:
  /// **'Model name is required'**
  String get validatorModelRequired;

  /// No description provided for @validatorColorRequired.
  ///
  /// In en, this message translates to:
  /// **'Color is required'**
  String get validatorColorRequired;

  /// No description provided for @validatorYearRequired.
  ///
  /// In en, this message translates to:
  /// **'Manufacturing year is required'**
  String get validatorYearRequired;

  /// No description provided for @validatorMileageRequired.
  ///
  /// In en, this message translates to:
  /// **'Mileage is required'**
  String get validatorMileageRequired;

  /// No description provided for @selectSubCategory.
  ///
  /// In en, this message translates to:
  /// **'Select sub-category'**
  String get selectSubCategory;

  /// No description provided for @selectBrand.
  ///
  /// In en, this message translates to:
  /// **'Select brand'**
  String get selectBrand;

  /// No description provided for @selectFuelType.
  ///
  /// In en, this message translates to:
  /// **'Select fuel type'**
  String get selectFuelType;

  /// No description provided for @selectTransmission.
  ///
  /// In en, this message translates to:
  /// **'Select transmission'**
  String get selectTransmission;

  /// No description provided for @selectDrivetrain.
  ///
  /// In en, this message translates to:
  /// **'Select drivetrain'**
  String get selectDrivetrain;

  /// No description provided for @selectCondition.
  ///
  /// In en, this message translates to:
  /// **'Select condition'**
  String get selectCondition;

  /// No description provided for @selectFrameMaterial.
  ///
  /// In en, this message translates to:
  /// **'Select frame material'**
  String get selectFrameMaterial;

  /// No description provided for @selectSuspension.
  ///
  /// In en, this message translates to:
  /// **'Select suspension type'**
  String get selectSuspension;

  /// No description provided for @selectBrakeType.
  ///
  /// In en, this message translates to:
  /// **'Select brake type'**
  String get selectBrakeType;

  /// No description provided for @selectOwnershipHistory.
  ///
  /// In en, this message translates to:
  /// **'Select ownership history'**
  String get selectOwnershipHistory;

  /// No description provided for @selectAccidentHistory.
  ///
  /// In en, this message translates to:
  /// **'Select accident history'**
  String get selectAccidentHistory;

  /// No description provided for @selectInsuranceStatus.
  ///
  /// In en, this message translates to:
  /// **'Select insurance status'**
  String get selectInsuranceStatus;

  /// No description provided for @vehicleLabel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get vehicleLabel;

  /// No description provided for @motorcycleLabel.
  ///
  /// In en, this message translates to:
  /// **'Motorcycle'**
  String get motorcycleLabel;

  /// No description provided for @bicycleLabel.
  ///
  /// In en, this message translates to:
  /// **'Bicycle'**
  String get bicycleLabel;

  /// No description provided for @brandSubcategoryChip.
  ///
  /// In en, this message translates to:
  /// **'{brand} • {subcategory}'**
  String brandSubcategoryChip(String brand, String subcategory);

  /// No description provided for @publishDraft.
  String get publishDraft;

  /// No description provided for @publish.
  String get publish;

  /// No description provided for @publishTooltip.
  String get publishTooltip;

  /// No description provided for @publishConfirmMessage.
  String publishConfirmMessage(String name, String id);

  /// No description provided for @auctionPublished.
  String get auctionPublished;

  /// No description provided for @auctionSoftDeleted.
  String get auctionSoftDeleted;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'rw'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'rw':
      return AppLocalizationsRw();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
