// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'E-CYAMUNARA';

  @override
  String get appSubtitle => 'ONLINE VEHICLE AUCTION PLATFORM';

  @override
  String get officialSystem => 'OFFICIAL RNP E-AUCTION SYSTEM';

  @override
  String get login => 'Login';

  @override
  String get loginSubtitle => 'Access your police-backed auction account.';

  @override
  String get loginButton => 'LOGIN';

  @override
  String get loginAsAdmin => 'LOGIN AS ADMIN';

  @override
  String get adminLogin => 'Admin Login';

  @override
  String get adminPortal => 'POLICE REGION ADMIN PORTAL';

  @override
  String get authorizedOnly => 'Authorized Personnel Only';

  @override
  String get adminSecurityNote =>
      'This portal is for authorized Rwanda National Police officers only. Any unauthorized access attempts are monitored and logged.';

  @override
  String get backToClientLogin => 'Back to Client Login';

  @override
  String get register => 'Register';

  @override
  String get createAccount => 'Create Account';

  @override
  String get registerSubtitle => 'Register to start bidding';

  @override
  String get registerButton => 'REGISTER';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get noAccount => 'Don\'t have an account?';

  @override
  String get phoneNumber => 'PHONE NUMBER';

  @override
  String get phoneNumberLabel => 'Phone Number';

  @override
  String get password => 'PASSWORD';

  @override
  String get passwordLabel => 'Password';

  @override
  String get confirmPassword => 'CONFIRM PASSWORD';

  @override
  String get fullNames => 'FULL NAMES';

  @override
  String get fullName => 'Full Name';

  @override
  String get nationalId => 'NATIONAL ID';

  @override
  String get nationalIdLabel => 'National ID';

  @override
  String get nationalIdCannotChange =>
      'National ID cannot be changed after creation';

  @override
  String get district => 'DISTRICT';

  @override
  String get selectDistrict => 'SELECT YOUR DISTRICT';

  @override
  String get selectDistrictHint => 'Select district';

  @override
  String get pleaseSelectDistrict => 'Please select your district';

  @override
  String get forgot => 'Forgot?';

  @override
  String get or => 'OR';

  @override
  String get required => 'Required';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get resetPasswordButton => 'RESET PASSWORD';

  @override
  String get passwordResetSuccess =>
      'Password reset successfully. Check your SMS.';

  @override
  String get newPassword => 'New Password';

  @override
  String get confirmNewPassword => 'Confirm New Password';

  @override
  String get changePasswordButton => 'CHANGE PASSWORD';

  @override
  String get enterConfirmNewPassword => 'Enter and confirm your new password';

  @override
  String get changePassword => 'Change Password';

  @override
  String get welcomeBack => 'Welcome Back,';

  @override
  String get regionSelectSubtitle =>
      'Select a region to view available auctions';

  @override
  String get chooseRegion => 'Choose Region';

  @override
  String get canChangeRegion =>
      'You can change region anytime from the Home screen';

  @override
  String get dashboard => 'DASHBOARD';

  @override
  String welcomeUser(String name) {
    return 'Welcome, $name';
  }

  @override
  String get activeAuctions => 'Active Auctions';

  @override
  String get searchAuctions => 'Search auctions...';

  @override
  String get all => 'All';

  @override
  String get cars => 'Cars';

  @override
  String get motorcycles => 'Motorcycles';

  @override
  String get bicycles => 'Bicycles';

  @override
  String noAuctionsInRegion(String region) {
    return 'No active auctions in the $region Region.\nCheck back later.';
  }

  @override
  String get auctionDetails => 'Auction Details';

  @override
  String get minimumPrice => 'MINIMUM PRICE';

  @override
  String get totalBidders => 'TOTAL\nBIDDERS';

  @override
  String get currentHighestBid => 'Current\nHighest Bid';

  @override
  String get auctionEnded => 'Auction Ended';

  @override
  String countdownRemaining(String countdown) {
    return '$countdown Remaining';
  }

  @override
  String get updateYourBid => 'UPDATE YOUR BID';

  @override
  String get placeYourBid => 'PLACE YOUR BID';

  @override
  String get updateBidButton => 'UPDATE BID';

  @override
  String get placeBidButton => 'PLACE BID';

  @override
  String get auctionHasEnded => 'This auction has ended';

  @override
  String get biddingAgreement =>
      'By bidding you agree to the RNP Auction Terms';

  @override
  String get vehicleSpecs => 'Vehicle Specifications';

  @override
  String get description => 'Description';

  @override
  String get category => 'Category';

  @override
  String get condition => 'Condition';

  @override
  String get plateNumber => 'Plate Number';

  @override
  String get postedBy => 'Posted By';

  @override
  String failedToLoadAuction(String error) {
    return 'Failed to load auction: $error';
  }

  @override
  String get goBack => 'Go Back';

  @override
  String get loadingAccount => 'Loading your account, please wait...';

  @override
  String get pleaseLogin => 'Please log in to place a bid';

  @override
  String get startDate => 'START DATE';

  @override
  String get endDate => 'END DATE';

  @override
  String get conditionLabel => 'CONDITION';

  @override
  String get plateNumberLabel => 'PLATE NUMBER';

  @override
  String get updateBidTitle => 'Update Your Bid';

  @override
  String get placeBidTitle => 'Place Your Bid';

  @override
  String get yourCurrentBid => 'Your Current Bid';

  @override
  String get yourBidAmount => 'Your Bid Amount (RWF)';

  @override
  String get region => 'Region';

  @override
  String get myBids => 'MY BIDS';

  @override
  String get total => 'TOTAL';

  @override
  String get winning => 'WINNING';

  @override
  String get won => 'WON';

  @override
  String get active => 'Active';

  @override
  String get lost => 'Lost';

  @override
  String get noBidsYet => 'No bids yet...';

  @override
  String noFilterBids(String filter) {
    return 'No $filter bids.';
  }

  @override
  String get bidUpdated => 'Bid Updated';

  @override
  String get bidPlaced => 'Bid Placed';

  @override
  String get bidUpdatedTitle => 'Bid Updated!';

  @override
  String get bidPlacedTitle => 'Bid Successfully Placed!';

  @override
  String get bidUpdatedMessage =>
      'Your bid has been updated in the\nRwanda National Police ledger.';

  @override
  String get bidPlacedMessage =>
      'Your bid has been submitted and registered to the\nRwanda National Police ledger.';

  @override
  String get bidReference => 'BID REFERENCE';

  @override
  String get itemDetails => 'ITEM DETAILS';

  @override
  String get yourBidAmount2 => 'YOUR BID AMOUNT';

  @override
  String submittedOn(String date) {
    return 'Submitted On $date';
  }

  @override
  String get currentStatus => 'CURRENT STATUS';

  @override
  String get currentlyWinning => 'CURRENTLY WINNING';

  @override
  String get bidRegistered => 'BID REGISTERED';

  @override
  String get viewMyBids => 'VIEW MY BIDS';

  @override
  String get backToHome => 'Back to Home';

  @override
  String get notifications => 'Notifications';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get bids => 'Bids';

  @override
  String get auctions => 'Auctions';

  @override
  String get results => 'Results';

  @override
  String get noNotificationsYet => 'No notifications yet';

  @override
  String noFilterNotifications(String filter) {
    return 'No $filter notifications';
  }

  @override
  String get notifyAboutBids =>
      'We\'ll notify you about bids, auction results, and more.';

  @override
  String get winningStreak => 'Winning Streak?';

  @override
  String get keepBidding => 'Keep bidding to stay on top.';

  @override
  String get viewAuctions => 'VIEW AUCTIONS';

  @override
  String get viewAuction => 'View Auction';

  @override
  String get markAsRead => 'Mark as Read';

  @override
  String get close => 'Close';

  @override
  String get myProfile => 'My Profile';

  @override
  String get activeClient => 'ACTIVE CLIENT';

  @override
  String get accountInformation => 'ACCOUNT INFORMATION';

  @override
  String get preferences => 'PREFERENCES';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get kinyarwanda => 'Kinyarwanda';

  @override
  String get auctionRegion => 'Auction Region';

  @override
  String get security => 'SECURITY';

  @override
  String get support => 'SUPPORT';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get helpCenter => 'Help Center';

  @override
  String get aboutApp => 'About E-Cyamunara';

  @override
  String get logout => 'LOGOUT';

  @override
  String get logoutTitle => 'Logout';

  @override
  String get logoutConfirmMessage => 'Are you sure you want to logout?';

  @override
  String get cancel => 'Cancel';

  @override
  String get totalBids => 'TOTAL BIDS';

  @override
  String get joined => 'JOINED';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get saveChanges => 'SAVE CHANGES';

  @override
  String get passwordChangedSuccess => 'Password changed successfully';

  @override
  String get profileUpdatedSuccess => 'Profile updated successfully';

  @override
  String get profileUpdatedPhotoFailed =>
      'Profile updated. Photo upload failed.';

  @override
  String get home => 'Home';

  @override
  String get feedbackNav => 'Feedback';

  @override
  String get myBidsNav => 'My Bids';

  @override
  String get profile => 'Profile';

  @override
  String get endsSoon => 'ENDS SOON';

  @override
  String get timeLeft => 'TIME LEFT';

  @override
  String get currentBid => 'Current Bid';

  @override
  String get bidNow => 'BID NOW';

  @override
  String get yourBidLabel => 'Your Bid:';

  @override
  String get updateBid => 'Update Bid';

  @override
  String get viewDetails => 'View Details';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get timeExpired => 'Time expired';

  @override
  String daysHoursRemaining(int d, int h) {
    return '${d}d ${h}h remaining';
  }

  @override
  String hoursMinutesRemaining(int h, int m) {
    return '${h}h ${m}m remaining';
  }

  @override
  String minutesRemaining(int m) {
    return '${m}m remaining';
  }

  @override
  String get wonBadge => 'Won';

  @override
  String get lostBadge => 'Lost';

  @override
  String get winningBadge => 'Winning';

  @override
  String get outbidBadge => 'Outbid';

  @override
  String get highestBadge => 'HIGHEST';

  @override
  String get noAuctionsAvailable => 'No auctions available';

  @override
  String get adminDashboard => 'ADMIN DASHBOARD';

  @override
  String get activeAuctionsCount => 'ACTIVE AUCTIONS';

  @override
  String get bidsToday => 'BIDS TODAY';

  @override
  String get closedAuctions => 'CLOSED AUCTIONS';

  @override
  String get registeredClients => 'REGISTERED\nCLIENTS';

  @override
  String get recentAuctions => 'Recent Auctions';

  @override
  String get seeAll => 'See All';

  @override
  String get failedToLoadStats => 'Failed to load stats';

  @override
  String get retry => 'Retry';

  @override
  String get failedToLoadRecentAuctions => 'Failed to load recent auctions';

  @override
  String get clientFeedback => 'Client Feedback';

  @override
  String get viewFeedbackDesc =>
      'View feedback submitted by clients in your region';

  @override
  String get regionAdmin => 'Region Admin';

  @override
  String regionAdminTitle(String region) {
    return '$region Region Admin';
  }

  @override
  String get admin => 'ADMIN';

  @override
  String get homeNav => 'HOME';

  @override
  String get auctionsNav => 'AUCTIONS';

  @override
  String get clientsNav => 'CLIENTS';

  @override
  String get reportsNav => 'REPORTS';

  @override
  String get profileNav => 'PROFILE';

  @override
  String get live => 'LIVE';

  @override
  String get ended => 'ENDED';

  @override
  String get draft => 'DRAFT';

  @override
  String get winningBid => 'WINNING BID';

  @override
  String get currentBidAdmin => 'CURRENT BID';

  @override
  String get manage => 'Manage';

  @override
  String get allowed => 'ALLOWED';

  @override
  String get denied => 'DENIED';

  @override
  String get suspended => 'SUSPENDED';

  @override
  String get winsCount => 'Wins';

  @override
  String get bidsCount => 'Bids';

  @override
  String get viewReport => 'View Report';

  @override
  String get closeAuctionTooltip => 'Close Auction';

  @override
  String get postNewAuction => 'POST NEW AUCTION';

  @override
  String get editAuction => 'EDIT AUCTION';

  @override
  String get sovereignLedger => 'SOVEREIGN LEDGER';

  @override
  String get registerAssets => 'Register Assets';

  @override
  String get formalDocumentation =>
      'Fill in the formal documentation for this asset.';

  @override
  String get itemInformation => 'ITEM INFORMATION';

  @override
  String get assetName => 'ASSET NAME';

  @override
  String get categoryLabel => 'CATEGORY';

  @override
  String get plateNumberField => 'PLATE NUMBER';

  @override
  String get conditionField => 'CONDITION';

  @override
  String get itemPhotos => 'ITEM PHOTOS';

  @override
  String get photosCannotChange => 'Photos cannot be changed after posting.';

  @override
  String photosSelected(int count) {
    return '$count/5 photos selected';
  }

  @override
  String get auctionDetailsSection => 'AUCTION DETAILS';

  @override
  String get startingPrice => 'STARTING PRICE (RWF)';

  @override
  String get storageRegion => 'STORAGE REGION';

  @override
  String get descriptionField => 'DESCRIPTION';

  @override
  String get postAuction => 'POST AUCTION';

  @override
  String get saveAsDraft => 'SAVE AS DRAFT';

  @override
  String get saveChangesButton => 'SAVE CHANGES';

  @override
  String get auctionUpdatedSuccess => 'Auction updated successfully!';

  @override
  String get auctionSavedDraft => 'Auction saved as draft';

  @override
  String get auctionPostedSuccess => 'Auction posted successfully!';

  @override
  String get selectDatesError => 'Please select start and end dates';

  @override
  String get endDateAfterStartError => 'End date must be after start date';

  @override
  String get upload => 'UPLOAD';

  @override
  String get addPhotos => 'Add Photos';

  @override
  String get tapToAddPhotos => 'Tap to add photos';

  @override
  String get manageAuctions => 'Manage Auctions';

  @override
  String get searchAuctionLots => 'Search auction lots, vehicles, or IDs...';

  @override
  String get deleteAuction => 'Delete Auction';

  @override
  String deleteConfirmMessage(String name, String id) {
    return 'Delete \"$name\" (LOT #$id)?\n\nThis will permanently remove the auction and all its photos. This action cannot be undone.';
  }

  @override
  String get delete => 'DELETE';

  @override
  String get auctionDeleted => 'Auction deleted.';

  @override
  String get failedToLoadAuctions => 'Failed to load auctions';

  @override
  String noAuctionsMatch(String query) {
    return 'No auctions match \"$query\"';
  }

  @override
  String noAuctionsYet(String filter) {
    return 'No $filter auctions yet.';
  }

  @override
  String get viewBids => 'View Bids';

  @override
  String get closeAuctionScreen => 'Close Auction';

  @override
  String get bidDetails => 'Bid Details';

  @override
  String get noBidsForAuction => 'No bids for this auction yet';

  @override
  String get clientManagement => 'CLIENT MANAGEMENT';

  @override
  String get searchClients => 'Search by name, ID, or email...';

  @override
  String get failedToLoadClients => 'Failed to load clients';

  @override
  String get suspendClient => 'Suspend Client';

  @override
  String get suspendClientMessage =>
      'This will prevent the client from placing bids. You can reactivate them at any time.';

  @override
  String get suspend => 'SUSPEND';

  @override
  String get activateClient => 'Activate Client';

  @override
  String get activateClientMessage =>
      'This will restore full bidding access for this client.';

  @override
  String get activate => 'ACTIVATE';

  @override
  String get clientSuspended => 'Client suspended.';

  @override
  String get clientActivated => 'Client activated.';

  @override
  String noClientsMatch(String query) {
    return 'No clients match \"$query\"';
  }

  @override
  String noClientsYet(String filter) {
    return 'No $filter clients.';
  }

  @override
  String get phone => 'PHONE';

  @override
  String get districtLabel => 'DISTRICT';

  @override
  String get province => 'PROVINCE';

  @override
  String get lastLogin => 'LAST LOGIN';

  @override
  String get regionReports => 'Region Reports';

  @override
  String get generateReport => 'Generate Report';

  @override
  String get reportGenerated => 'Report generated successfully';

  @override
  String get failedToGenerateReport => 'Failed to generate report';

  @override
  String get downloadReport => 'Download Report';

  @override
  String get adminFeedback => 'Client Feedback';

  @override
  String get noFeedbackYet => 'No feedback submitted yet';

  @override
  String feedbackFrom(String name) {
    return 'Feedback from $name';
  }

  @override
  String get editRegionAdmin => 'Edit Region Admin';

  @override
  String get addRegionAdmin => 'Add Region Admin';

  @override
  String get adminInformation => 'ADMIN INFORMATION';

  @override
  String get temporaryPasswordNote =>
      'A secure temporary password will be generated automatically.';

  @override
  String get regionAssignment => 'REGION ASSIGNMENT';

  @override
  String get regionCannotChange => 'Region cannot be changed after creation.';

  @override
  String get permissions => 'PERMISSIONS';

  @override
  String get postAuctionsPermission => 'Post Auctions';

  @override
  String get createNewLots => 'Create new vehicle lots';

  @override
  String get manageClientsPermission => 'Manage Clients';

  @override
  String get reviewBidderDocs => 'Review bidder documentation';

  @override
  String get viewReportsPermission => 'View Reports';

  @override
  String get accessRegionalStats => 'Access regional statistics';

  @override
  String get closeAuctionsPermission => 'Close Auctions';

  @override
  String get manuallyCloseAndAward => 'Manually close and award';

  @override
  String get adminCreated => 'Admin Created';

  @override
  String adminCreatedFor(String name, String region) {
    return '$name has been created for the $region Region.';
  }

  @override
  String get temporaryPassword => 'Temporary Password';

  @override
  String get savePasswordWarning =>
      'Save this password — it cannot be retrieved after closing this dialog.';

  @override
  String get done => 'Done';

  @override
  String get copyPassword => 'Copy password';

  @override
  String get passwordCopied => 'Password copied to clipboard';

  @override
  String get pleaseSelectRegion => 'Please select a region';

  @override
  String creationFailed(String error) {
    return 'Creation failed: $error';
  }

  @override
  String get adminUpdatedSuccess => 'Admin updated successfully';

  @override
  String failedToUpdateAdmin(String error) {
    return 'Failed to update admin: $error';
  }

  @override
  String get superAdminDashboard => 'SUPER ADMIN';

  @override
  String get commissioner => 'Commissioner';

  @override
  String get superAdministrator => 'Super Administrator';

  @override
  String get nationalRevenue => 'NATIONAL REVENUE';

  @override
  String get totalCollectedAllTime => 'Total Collected — All Time';

  @override
  String closedAuctionsCount(int count) {
    return '$count closed auctions';
  }

  @override
  String get regionsOverview => 'Regions Overview';

  @override
  String get adminActivity => 'Admin Activity';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get appSettings => 'App Settings';

  @override
  String get nationalReports => 'National Reports';

  @override
  String get totalAuctions => 'TOTAL AUCTIONS';

  @override
  String get totalBidsLabel => 'TOTAL BIDS';

  @override
  String get clients => 'CLIENTS';

  @override
  String get regionAdmins => 'REGION ADMINS';

  @override
  String get noRegionAdmins =>
      'No region admins yet.\nTap + to add the first admin.';

  @override
  String get noAdminActivity => 'No admin activity yet';

  @override
  String get loadingRegions => 'Loading regions…';

  @override
  String auctionsCount(int count) {
    return '$count auctions';
  }

  @override
  String regionLabel(String region) {
    return '$region Region';
  }

  @override
  String get manageAdmins => 'Manage Admins';

  @override
  String get searchAdmins => 'Search admins...';

  @override
  String noAdminsMatch(String query) {
    return 'No admins match \"$query\"';
  }

  @override
  String get noAdminsYet => 'No admins yet';

  @override
  String get superAdminNav1 => 'DASHBOARD';

  @override
  String get superAdminNav2 => 'ADMINS';

  @override
  String get superAdminNav3 => 'REPORTS';

  @override
  String get superAdminNav4 => 'SETTINGS';

  @override
  String get superAdminNav5 => 'PROFILE';

  @override
  String get feedbackTitle => 'Feedback';

  @override
  String get feedbackHeaderTitle => 'E-CYAMUNARA Feedback';

  @override
  String get auctionFeedbackTitle => 'E-CYAMUNARA Auction\nFeedback';

  @override
  String get helpImprove => 'Help us improve our platform';

  @override
  String get helpImproveService => 'Help us improve our service';

  @override
  String get rateExperience => 'Rate Your Experience';

  @override
  String get howSatisfied => 'How satisfied are you with our platform?';

  @override
  String get howSatisfiedService => 'How satisfied are you with our service?';

  @override
  String get whatWentWell => 'What went well?';

  @override
  String get additionalComments => 'Additional Comments';

  @override
  String get shareExperience => 'Share your experience...';

  @override
  String get wouldRecommend => 'Would you recommend E-CYAMUNARA?';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get submitFeedback => 'SUBMIT FEEDBACK';

  @override
  String get thankYouFeedback => 'Thank you for your feedback!';

  @override
  String failedToSubmit(String error) {
    return 'Failed to submit: $error';
  }

  @override
  String get thankYouRnp =>
      'Thank you for helping Rwanda National Police improve';

  @override
  String get indicateRecommend => 'Please indicate if you would recommend';

  @override
  String get auctionItem => 'AUCTION ITEM';

  @override
  String get date => 'DATE';

  @override
  String get tagEasyToUse => 'Easy to Use';

  @override
  String get tagFastProcess => 'Fast Process';

  @override
  String get tagTransparency => 'Transparency';

  @override
  String get tagCommunication => 'Communication';

  @override
  String get tagPaymentFlow => 'Payment Flow';

  @override
  String get tagDocumentation => 'Documentation';

  @override
  String get ratingPoor => 'Poor';

  @override
  String get ratingFair => 'Fair';

  @override
  String get ratingGood => 'Good';

  @override
  String get ratingVeryGood => 'Very Good';

  @override
  String get ratingExcellent => 'Excellent';

  @override
  String get validatorPhoneRequired => 'Phone number is required';

  @override
  String get validatorPhoneInvalid =>
      'Enter a valid Rwanda phone number (e.g. 078XXXXXXX)';

  @override
  String get validatorNationalIdRequired => 'National ID is required';

  @override
  String get validatorNationalIdLength =>
      'National ID must be exactly 16 digits';

  @override
  String get validatorNationalIdDigitsOnly =>
      'National ID must contain digits only';

  @override
  String get validatorPasswordRequired => 'Password is required';

  @override
  String get validatorPasswordTooShort =>
      'Password must be at least 8 characters';

  @override
  String get validatorPasswordUppercase => 'Add at least one uppercase letter';

  @override
  String get validatorPasswordNumber => 'Add at least one number';

  @override
  String get validatorPasswordSpecial =>
      'Add at least one special character (!@#\$%^&*)';

  @override
  String get validatorConfirmRequired => 'Please confirm your password';

  @override
  String get validatorPasswordsNoMatch => 'Passwords do not match';

  @override
  String get validatorFullNameRequired => 'Full name is required';

  @override
  String get validatorNameTooShort =>
      'Name is too short (minimum 3 characters)';

  @override
  String get validatorBidRequired => 'Bid amount is required';

  @override
  String get validatorBidInvalid => 'Enter a valid amount';

  @override
  String get validatorBidZero => 'Bid must be greater than zero';

  @override
  String validatorBidTooLow(String minimum) {
    return 'Bid must be higher than RWF $minimum';
  }

  @override
  String get validatorDescriptionRequired => 'Description is required';

  @override
  String get validatorDescriptionTooShort =>
      'Description must be at least 20 characters';

  @override
  String get validatorCommentTooLong =>
      'Comment must not exceed 250 characters';

  @override
  String get validatorEndDateRequired => 'End date is required';

  @override
  String get validatorEndDateBeforeStart => 'End date must be after start date';

  @override
  String get validatorEndDatePast => 'End date must be in the future';

  @override
  String get loading => 'Loading...';

  @override
  String get error => 'Error';

  @override
  String get success => 'Success';

  @override
  String get confirm => 'Confirm';

  @override
  String get save => 'Save';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get create => 'Create';

  @override
  String get update => 'Update';

  @override
  String get search => 'Search';

  @override
  String get filter => 'Filter';

  @override
  String get refresh => 'Refresh';

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get submit => 'Submit';

  @override
  String get superAdminBadge => 'SUPER ADMIN';

  @override
  String get regionAdminBadge => 'REGION ADMIN';

  @override
  String get pendingBadge => 'PENDING';

  @override
  String get activeBadge => 'ACTIVE';

  @override
  String get offBadge => 'OFF';

  @override
  String get adminProfile => 'Admin Profile';

  @override
  String get postedStat => 'POSTED';

  @override
  String get closedStat => 'CLOSED';

  @override
  String get statusStat => 'STATUS';

  @override
  String get roleLabel => 'ROLE';

  @override
  String get accountStatusLabel => 'ACCOUNT STATUS';

  @override
  String get memberSince => 'MEMBER SINCE';

  @override
  String get profileLoadError =>
      'Could not refresh profile. Showing last known data.';

  @override
  String get neverRecorded => 'Never recorded';

  @override
  String get fullNameEmpty => 'Full name cannot be empty';

  @override
  String updateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String passwordChangeFailed(String error) {
    return 'Failed to change password: $error';
  }

  @override
  String get updatePasswordDesc => 'Update your account password';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get failedToLoadAdmins => 'Failed to load admins';

  @override
  String get tapToViewDetails => 'Tap to view details';

  @override
  String get notOnRecord => 'Not on record';

  @override
  String get addNewAdmin => 'Add new admin';

  @override
  String get suspendAdmin => 'Suspend Admin';

  @override
  String suspendAdminMessage(String name, String region) {
    return 'Suspend $name ($region)?\n\nThey will be immediately signed out and unable to log in until re-activated.';
  }

  @override
  String get activateAdmin => 'Activate Admin';

  @override
  String activateAdminMessage(String name, String region) {
    return 'Re-activate $name ($region)?\n\nThey will be able to log in immediately.';
  }

  @override
  String adminSuspendedMsg(String name) {
    return '$name suspended';
  }

  @override
  String adminActivatedMsg(String name) {
    return '$name activated';
  }

  @override
  String get sessionExpiredError => 'Session expired — please log in again';

  @override
  String get createAdmin => 'CREATE ADMIN';

  @override
  String get fiscalPerformance => 'FISCAL PERFORMANCE';

  @override
  String get nationwideLedger => 'Nationwide Ledger';

  @override
  String get totalRevenue => 'TOTAL REVENUE';

  @override
  String get auctionsLabel => 'AUCTIONS';

  @override
  String get bidsLabel => 'BIDS';

  @override
  String get performanceByRegion => 'Performance by Region';

  @override
  String get failedToLoadRegionData => 'Failed to load region data';

  @override
  String get noAuctionDataForPeriod => 'No auction data for this period';

  @override
  String get reportReady => 'Report Ready';

  @override
  String get reportCopyLinkInstruction =>
      'Copy the link below and open it in your browser:';

  @override
  String get reportLinkValidity => 'Link is valid for 7 days.';

  @override
  String get copyUrl => 'Copy URL';

  @override
  String get urlCopied => 'URL copied to clipboard';

  @override
  String get reportReadyNoUrl =>
      'Report generated but no download URL returned';

  @override
  String downloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get superAdminProfile => 'Super Admin Profile';

  @override
  String get adminsBadge => 'ADMINS';

  @override
  String get regionsCount => 'REGIONS';

  @override
  String get systemAccess => 'SYSTEM ACCESS';

  @override
  String get manageRegionAdminsPermission => 'Manage Region Admins';

  @override
  String get viewAllRegionsPermission => 'View All Regions';

  @override
  String get systemConfigPermission => 'System Configuration';

  @override
  String get auditLogsPermission => 'Audit Logs';

  @override
  String get authorityLabel => 'AUTHORITY';

  @override
  String get nationalLevelRnp => 'National Level — RNP';

  @override
  String get basicInformation => 'BASIC INFORMATION';

  @override
  String get technicalSpecs => 'TECHNICAL SPECIFICATIONS';

  @override
  String get ownershipSection => 'OWNERSHIP & HISTORY';

  @override
  String get mainCategoryLabel => 'MAIN CATEGORY';

  @override
  String get subCategoryLabel => 'SUB-CATEGORY';

  @override
  String get brandLabel => 'BRAND';

  @override
  String get modelField => 'MODEL';

  @override
  String get manufacturingYearLabel => 'MANUFACTURING YEAR';

  @override
  String get colorField => 'COLOR';

  @override
  String get mileageField => 'MILEAGE (KM)';

  @override
  String get fuelTypeField => 'FUEL TYPE';

  @override
  String get transmissionField => 'TRANSMISSION';

  @override
  String get engineSizeField => 'ENGINE SIZE (L)';

  @override
  String get engineCcField => 'ENGINE CC';

  @override
  String get drivetrainField => 'DRIVETRAIN';

  @override
  String get seatingCapacityField => 'SEATING CAPACITY';

  @override
  String get frameMaterialField => 'FRAME MATERIAL';

  @override
  String get gearCountField => 'GEAR COUNT';

  @override
  String get suspensionTypeField => 'SUSPENSION TYPE';

  @override
  String get brakeTypeField => 'BRAKE TYPE';

  @override
  String get ownershipHistoryField => 'OWNERSHIP HISTORY';

  @override
  String get accidentHistoryField => 'ACCIDENT HISTORY';

  @override
  String get insuranceStatusField => 'INSURANCE STATUS';

  @override
  String get optionPetrol => 'Petrol';

  @override
  String get optionDiesel => 'Diesel';

  @override
  String get optionHybrid => 'Hybrid';

  @override
  String get optionElectric => 'Electric';

  @override
  String get optionAutomatic => 'Automatic';

  @override
  String get optionManual => 'Manual';

  @override
  String get optionCvt => 'CVT';

  @override
  String get optionExcellent => 'Excellent';

  @override
  String get optionVeryGood => 'Very Good';

  @override
  String get optionGood => 'Good';

  @override
  String get optionFair => 'Fair';

  @override
  String get optionPoor => 'Poor';

  @override
  String get optionFirstOwner => 'First Owner';

  @override
  String get optionSecondOwner => 'Second Owner';

  @override
  String get optionThirdOwner => 'Third Owner';

  @override
  String get optionFleetVehicle => 'Fleet Vehicle';

  @override
  String get optionInsured => 'Insured';

  @override
  String get optionExpiredInsurance => 'Expired';

  @override
  String get optionNeverInsured => 'Never Insured';

  @override
  String get optionUnknown => 'Unknown';

  @override
  String get optionNoAccidents => 'No Accidents';

  @override
  String get optionMinorDamage => 'Minor Damage';

  @override
  String get optionMajorDamage => 'Major Damage';

  @override
  String validatorYearRange(int year) {
    return 'Year must be between 1900 and $year';
  }

  @override
  String get validatorMileageNegative => 'Mileage cannot be negative';

  @override
  String get validatorEngineCcRequired =>
      'Engine CC is required for motorcycles';

  @override
  String get validatorEngineSizeRequired =>
      'Engine size is required for vehicles';

  @override
  String get validatorTransmissionRequired =>
      'Transmission is required for vehicles';

  @override
  String get validatorGearCountRequired =>
      'Gear count is required for bicycles';

  @override
  String get validatorFuelTypeRequired => 'Fuel type is required';

  @override
  String get validatorSubCategoryRequired => 'Sub-category is required';

  @override
  String get validatorBrandRequired => 'Brand is required';

  @override
  String get validatorModelRequired => 'Model name is required';

  @override
  String get validatorColorRequired => 'Color is required';

  @override
  String get validatorYearRequired => 'Manufacturing year is required';

  @override
  String get validatorMileageRequired => 'Mileage is required';

  @override
  String get selectSubCategory => 'Select sub-category';

  @override
  String get selectBrand => 'Select brand';

  @override
  String get selectFuelType => 'Select fuel type';

  @override
  String get selectTransmission => 'Select transmission';

  @override
  String get selectDrivetrain => 'Select drivetrain';

  @override
  String get selectCondition => 'Select condition';

  @override
  String get selectFrameMaterial => 'Select frame material';

  @override
  String get selectSuspension => 'Select suspension type';

  @override
  String get selectBrakeType => 'Select brake type';

  @override
  String get selectOwnershipHistory => 'Select ownership history';

  @override
  String get selectAccidentHistory => 'Select accident history';

  @override
  String get selectInsuranceStatus => 'Select insurance status';

  @override
  String get vehicleLabel => 'Vehicle';

  @override
  String get motorcycleLabel => 'Motorcycle';

  @override
  String get bicycleLabel => 'Bicycle';

  @override
  String brandSubcategoryChip(String brand, String subcategory) {
    return '$brand • $subcategory';
  }

  @override
  String get publishDraft => 'Publish Auction';

  @override
  String get publish => 'PUBLISH';

  @override
  String get publishTooltip => 'Publish Draft';

  @override
  String publishConfirmMessage(String name, String id) {
    return 'Publish "$name" (LOT #$id)?\n\nThis will make the auction live and visible to all clients. Bidding will begin immediately.';
  }

  @override
  String get auctionPublished => 'Auction published successfully!';

  @override
  String get auctionSoftDeleted => 'Auction removed from listings (bid history preserved).';
}
