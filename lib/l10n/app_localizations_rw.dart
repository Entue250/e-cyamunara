// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kinyarwanda (`rw`).
class AppLocalizationsRw extends AppLocalizations {
  AppLocalizationsRw([String locale = 'rw']) : super(locale);

  @override
  String get appTitle => 'E-CYAMUNARA';

  @override
  String get appSubtitle => 'ISOKO RY\'IMODOKA KU MUHANDA';

  @override
  String get officialSystem => 'SISITEMU YA RNP Y\'AMASOKO KU INTERNET';

  @override
  String get login => 'Injira';

  @override
  String get loginSubtitle => 'Injira muri konti yawe y\'isoko rya polisi.';

  @override
  String get loginButton => 'INJIRA';

  @override
  String get loginAsAdmin => 'INJIRA NKO UMUYOBOZI';

  @override
  String get adminLogin => 'Injira nk\'Umuyobozi';

  @override
  String get adminPortal => 'PORTAL Y\'UMUYOBOZI W\'AKARERE WA POLISI';

  @override
  String get authorizedOnly => 'Abantu Bemerewe Gusa';

  @override
  String get adminSecurityNote =>
      'Iyi portal ni iy\'abapolisi ba Rwanda National Police gusa. Ibigeragezo byose by\'abantu batemewe birasomwa kandi birabikwa.';

  @override
  String get backToClientLogin => 'Subira ku Kwinjira kw\'Umukiriya';

  @override
  String get register => 'Iyandikishe';

  @override
  String get createAccount => 'Fungura Konti';

  @override
  String get registerSubtitle => 'Iyandikishe gutangira gutanga ibiciro';

  @override
  String get registerButton => 'IYANDIKISHE';

  @override
  String get alreadyHaveAccount => 'Usanganywe konti?';

  @override
  String get noAccount => 'Nta konti ufite?';

  @override
  String get phoneNumber => 'NIMERO YA TELEFONI';

  @override
  String get phoneNumberLabel => 'Nimero ya Telefoni';

  @override
  String get password => 'IJAMBO RY\'IBANGA';

  @override
  String get passwordLabel => 'Ijambo ry\'Ibanga';

  @override
  String get confirmPassword => 'EMEZA IJAMBO RY\'IBANGA';

  @override
  String get fullNames => 'AMAZINA YOMBI';

  @override
  String get fullName => 'Amazina Yombi';

  @override
  String get nationalId => 'INDANGAMUNTU';

  @override
  String get nationalIdLabel => 'Indangamuntu';

  @override
  String get nationalIdCannotChange =>
      'Indangamuntu ntishobora guhindurwa nyuma yo gukora';

  @override
  String get district => 'AKARERE';

  @override
  String get selectDistrict => 'HITAMO AKARERE KAWE';

  @override
  String get selectDistrictHint => 'Hitamo akarere';

  @override
  String get pleaseSelectDistrict => 'Hitamo akarere kawe';

  @override
  String get forgot => 'Wibagiwe?';

  @override
  String get or => 'CYANGWA';

  @override
  String get required => 'Birakenewe';

  @override
  String get resetPassword => 'Hindura Ijambo ry\'Ibanga';

  @override
  String get resetPasswordButton => 'HINDURA IJAMBO RY\'IBANGA';

  @override
  String get passwordResetSuccess =>
      'Ijambo ry\'ibanga ryahinduwe. Reba SMS yawe.';

  @override
  String get newPassword => 'Ijambo ry\'Ibanga Rishya';

  @override
  String get confirmNewPassword => 'Emeza Ijambo ry\'Ibanga Rishya';

  @override
  String get changePasswordButton => 'HINDURA IJAMBO RY\'IBANGA';

  @override
  String get enterConfirmNewPassword =>
      'Injiza kandi uemeze ijambo ry\'ibanga rishya';

  @override
  String get changePassword => 'Hindura Ijambo ry\'Ibanga';

  @override
  String get welcomeBack => 'Murakaza neza,';

  @override
  String get regionSelectSubtitle =>
      'Hitamo akarere kugira ngo urebe amasoko aboneka';

  @override
  String get chooseRegion => 'Hitamo Akarere';

  @override
  String get canChangeRegion =>
      'Ushobora guhindura akarere igihe cyose ukoresheje ikirahuri cya Ahabanza';

  @override
  String get dashboard => 'IMBONERAHAMWE';

  @override
  String welcomeUser(String name) {
    return 'Murakaza neza, $name';
  }

  @override
  String get activeAuctions => 'Amasoko Akora';

  @override
  String get searchAuctions => 'Shakisha amasoko...';

  @override
  String get all => 'Byose';

  @override
  String get cars => 'Imodoka';

  @override
  String get motorcycles => 'Moto';

  @override
  String get bicycles => 'Inginga';

  @override
  String noAuctionsInRegion(String region) {
    return 'Nta masoko akora mu Karere ka $region.\nSubira urebe nyuma.';
  }

  @override
  String get auctionDetails => 'Ibisobanuro by\'Isoko';

  @override
  String get minimumPrice => 'IGICIRO NTARENGWA';

  @override
  String get totalBidders => 'ABANTU\nBATANZE';

  @override
  String get currentHighestBid => 'Igiciro\nGikubye';

  @override
  String get auctionEnded => 'Isoko Ryarangiye';

  @override
  String countdownRemaining(String countdown) {
    return '$countdown Bisigaye';
  }

  @override
  String get updateYourBid => 'HINDURA IGICIRO CYAWE';

  @override
  String get placeYourBid => 'TANGA IGICIRO CYAWE';

  @override
  String get updateBidButton => 'HINDURA IGICIRO';

  @override
  String get placeBidButton => 'TANGA IGICIRO';

  @override
  String get auctionHasEnded => 'Iri soko ryarangiye';

  @override
  String get biddingAgreement =>
      'No gutanga igiciro uremeza amabwiriza ya RNP y\'Amasoko';

  @override
  String get vehicleSpecs => 'Ibisobanuro by\'Imodoka';

  @override
  String get description => 'Ibisobanuro';

  @override
  String get category => 'Icyiciro';

  @override
  String get condition => 'Imiterere';

  @override
  String get plateNumber => 'Indangamuntu y\'Imodoka';

  @override
  String get postedBy => 'Uwabitangiye';

  @override
  String failedToLoadAuction(String error) {
    return 'Guharura isoko byaretse: $error';
  }

  @override
  String get goBack => 'Subira Inyuma';

  @override
  String get loadingAccount => 'Gutangira konti yawe, tegereza...';

  @override
  String get pleaseLogin => 'Injira kugira ngo utange igiciro';

  @override
  String get startDate => 'ITARIKI Y\'INTANGIRIRO';

  @override
  String get endDate => 'ITARIKI Y\'IHEREZO';

  @override
  String get conditionLabel => 'IMITERERE';

  @override
  String get plateNumberLabel => 'INDANGAMUNTU Y\'IMODOKA';

  @override
  String get updateBidTitle => 'Hindura Igiciro Cyawe';

  @override
  String get placeBidTitle => 'Tanga Igiciro Cyawe';

  @override
  String get yourCurrentBid => 'Igiciro Cyawe Kiripo';

  @override
  String get yourBidAmount => 'Ingano y\'Igiciro Cyawe (RWF)';

  @override
  String get region => 'Akarere';

  @override
  String get myBids => 'IBICIRO BYANGE';

  @override
  String get total => 'BYOSE';

  @override
  String get winning => 'UTSINDA';

  @override
  String get won => 'WATSINZE';

  @override
  String get active => 'Akora';

  @override
  String get lost => 'Watsinzwe';

  @override
  String get noBidsYet => 'Nta biciro nawe...';

  @override
  String noFilterBids(String filter) {
    return 'Nta biciro bya $filter.';
  }

  @override
  String get bidUpdated => 'Igiciro Cyahinduwe';

  @override
  String get bidPlaced => 'Igiciro Gitanzwe';

  @override
  String get bidUpdatedTitle => 'Igiciro Cyahinduwe!';

  @override
  String get bidPlacedTitle => 'Igiciro Gitanzwe Neza!';

  @override
  String get bidUpdatedMessage =>
      'Igiciro cyawe cyahinduwe mu\ninyandiko ya Rwanda National Police.';

  @override
  String get bidPlacedMessage =>
      'Igiciro cyawe cyatanzwe kandi cyandikwa mu\ninyandiko ya Rwanda National Police.';

  @override
  String get bidReference => 'NUMERO Y\'IGICIRO';

  @override
  String get itemDetails => 'IBISOBANURO BY\'IGICURUZWA';

  @override
  String get yourBidAmount2 => 'INGANO Y\'IGICIRO CYAWE';

  @override
  String submittedOn(String date) {
    return 'Byatanzwe $date';
  }

  @override
  String get currentStatus => 'IMIMERERE UBU';

  @override
  String get currentlyWinning => 'UTSINDA UBU';

  @override
  String get bidRegistered => 'IGICIRO CYANDITSWE';

  @override
  String get viewMyBids => 'REBA IBICIRO BYANGE';

  @override
  String get backToHome => 'Subira Ahabanza';

  @override
  String get notifications => 'Imenyesha';

  @override
  String get markAllRead => 'Shyira byose ko birabwe';

  @override
  String get bids => 'Ibiciro';

  @override
  String get auctions => 'Amasoko';

  @override
  String get results => 'Ibisubizo';

  @override
  String get noNotificationsYet => 'Nta menyesha nawe';

  @override
  String noFilterNotifications(String filter) {
    return 'Nta menyesha ya $filter';
  }

  @override
  String get notifyAboutBids =>
      'Tuzakumenyesha ibijyanye n\'ibiciro, ibisubizo by\'amasoko, n\'ibindi.';

  @override
  String get winningStreak => 'Ukomeza Gutsinda?';

  @override
  String get keepBidding => 'Komeza gutanga ibiciro kuguma hejuru.';

  @override
  String get viewAuctions => 'REBA AMASOKO';

  @override
  String get viewAuction => 'Reba Isoko';

  @override
  String get markAsRead => 'Shyira ko Birabwe';

  @override
  String get close => 'Funga';

  @override
  String get myProfile => 'Umwirondoro Wange';

  @override
  String get activeClient => 'UMUKIRIYA UKORA';

  @override
  String get accountInformation => 'AMAKURU Y\'KONTI';

  @override
  String get preferences => 'IBIHITAMO';

  @override
  String get language => 'Ururimi';

  @override
  String get english => 'Icyongereza';

  @override
  String get kinyarwanda => 'Ikinyarwanda';

  @override
  String get auctionRegion => 'Akarere k\'Amasoko';

  @override
  String get security => 'UMUTEKANO';

  @override
  String get support => 'UBUFASHA';

  @override
  String get privacyPolicy => 'Amabwiriza y\'Ibanga';

  @override
  String get helpCenter => 'Indaro y\'Ubufasha';

  @override
  String get aboutApp => 'Ibisobanuro by\'E-Cyamunara';

  @override
  String get logout => 'SOHOKA';

  @override
  String get logoutTitle => 'Sohoka';

  @override
  String get logoutConfirmMessage => 'Urashaka gusohoka?';

  @override
  String get cancel => 'Hagarika';

  @override
  String get totalBids => 'IBICIRO BYOSE';

  @override
  String get joined => 'WINJIYE';

  @override
  String get editProfile => 'Hindura Umwirondoro';

  @override
  String get saveChanges => 'BIKA IMPINDUKA';

  @override
  String get passwordChangedSuccess => 'Ijambo ry\'ibanga ryahinduwe neza';

  @override
  String get profileUpdatedSuccess => 'Umwirondoro wahinduwe neza';

  @override
  String get profileUpdatedPhotoFailed =>
      'Umwirondoro wahinduwe. Kohereza ifoto byaretse.';

  @override
  String get home => 'Ahabanza';

  @override
  String get feedbackNav => 'Ibitekerezo';

  @override
  String get myBidsNav => 'Ibiciro Byange';

  @override
  String get profile => 'Umwirondoro';

  @override
  String get endsSoon => 'IRARANGIRA VUBA';

  @override
  String get timeLeft => 'IGIHE GISIGAYE';

  @override
  String get currentBid => 'Igiciro Kiripo';

  @override
  String get bidNow => 'TANGA IGICIRO';

  @override
  String get yourBidLabel => 'Igiciro Cyawe:';

  @override
  String get updateBid => 'Hindura Igiciro';

  @override
  String get viewDetails => 'Reba Ibisobanuro';

  @override
  String get somethingWentWrong => 'Hari ikintu cyaretse';

  @override
  String get timeExpired => 'Igihe cyararangiye';

  @override
  String daysHoursRemaining(int d, int h) {
    return '${d}d ${h}h bisigaye';
  }

  @override
  String hoursMinutesRemaining(int h, int m) {
    return '${h}h ${m}m bisigaye';
  }

  @override
  String minutesRemaining(int m) {
    return '${m}m bisigaye';
  }

  @override
  String get wonBadge => 'Watsinze';

  @override
  String get lostBadge => 'Watsinzwe';

  @override
  String get winningBadge => 'Utsinda';

  @override
  String get outbidBadge => 'Watsindwa';

  @override
  String get highestBadge => 'GIKUBYE';

  @override
  String get noAuctionsAvailable => 'Nta masoko aboneka';

  @override
  String get adminDashboard => 'IMBONERAHAMWE Y\'UMUYOBOZI';

  @override
  String get activeAuctionsCount => 'AMASOKO AKORA';

  @override
  String get bidsToday => 'IBICIRO UMUGOROBA';

  @override
  String get closedAuctions => 'AMASOKO YARANGIYE';

  @override
  String get registeredClients => 'ABAKIRIYA\nBANDITSWE';

  @override
  String get recentAuctions => 'Amasoko Mashya';

  @override
  String get seeAll => 'Reba Byose';

  @override
  String get failedToLoadStats => 'Guharura amakuru byaretse';

  @override
  String get retry => 'Ongera Ugerageze';

  @override
  String get failedToLoadRecentAuctions => 'Kuzana amasoko mashya byaretse';

  @override
  String get clientFeedback => 'Ibitekerezo by\'Abakiriya';

  @override
  String get viewFeedbackDesc =>
      'Reba ibitekerezo byatanzwe n\'abakiriya mu karere kawe';

  @override
  String get regionAdmin => 'Umuyobozi w\'Akarere';

  @override
  String regionAdminTitle(String region) {
    return 'Umuyobozi w\'Akarere ka $region';
  }

  @override
  String get admin => 'UMUYOBOZI';

  @override
  String get homeNav => 'AHABANZA';

  @override
  String get auctionsNav => 'AMASOKO';

  @override
  String get clientsNav => 'ABAKIRIYA';

  @override
  String get reportsNav => 'RAPORO';

  @override
  String get profileNav => 'UMWIRONDORO';

  @override
  String get live => 'NTANGIZWA';

  @override
  String get ended => 'YARANGIYE';

  @override
  String get draft => 'GASAKA';

  @override
  String get winningBid => 'IGICIRO GITSINDA';

  @override
  String get currentBidAdmin => 'IGICIRO KIRIPO';

  @override
  String get manage => 'Gucunga';

  @override
  String get allowed => 'BYEMEREWE';

  @override
  String get denied => 'BYANZWE';

  @override
  String get suspended => 'GIKUMIRWA';

  @override
  String get winsCount => 'Insinzi';

  @override
  String get bidsCount => 'Ibiciro';

  @override
  String get viewReport => 'Reba Raporo';

  @override
  String get closeAuctionTooltip => 'Funga Isoko';

  @override
  String get postNewAuction => 'TANGAZA ISOKO RISHYA';

  @override
  String get editAuction => 'HINDURA ISOKO';

  @override
  String get sovereignLedger => 'INYANDIKO YA LETA';

  @override
  String get registerAssets => 'Andika Ibintu';

  @override
  String get formalDocumentation => 'Uzuza inyandiko ya leta y\'iki kintu.';

  @override
  String get itemInformation => 'AMAKURU Y\'IGICURUZWA';

  @override
  String get assetName => 'IZINA RY\'IGICURUZWA';

  @override
  String get categoryLabel => 'ICYICIRO';

  @override
  String get plateNumberField => 'INDANGAMUNTU Y\'IMODOKA';

  @override
  String get conditionField => 'IMITERERE';

  @override
  String get itemPhotos => 'AMAFOTO Y\'IGICURUZWA';

  @override
  String get photosCannotChange =>
      'Amafoto ntashobora guhindurwa nyuma yo gutangaza.';

  @override
  String photosSelected(int count) {
    return 'Amafoto $count/5 yahiswemo';
  }

  @override
  String get auctionDetailsSection => 'AMAKURU Y\'ISOKO';

  @override
  String get startingPrice => 'IGICIRO CY\'INTANGIRIRO (RWF)';

  @override
  String get storageRegion => 'AKARERE K\'UBUBIKO';

  @override
  String get descriptionField => 'IBISOBANURO';

  @override
  String get postAuction => 'TANGAZA ISOKO';

  @override
  String get saveAsDraft => 'BIKA NKO GASAKA';

  @override
  String get saveChangesButton => 'BIKA IMPINDUKA';

  @override
  String get auctionUpdatedSuccess => 'Isoko ryahinduwe neza!';

  @override
  String get auctionSavedDraft => 'Isoko rybitswe nko gasaka';

  @override
  String get auctionPostedSuccess => 'Isoko ryatangajwe neza!';

  @override
  String get selectDatesError => 'Hitamo itariki y\'intangiriro n\'iherezo';

  @override
  String get endDateAfterStartError =>
      'Itariki y\'iherezo igomba kuba nyuma y\'iy\'intangiriro';

  @override
  String get upload => 'TANGA';

  @override
  String get addPhotos => 'Ongeraho Amafoto';

  @override
  String get tapToAddPhotos => 'Kanda kugira ngo wongeraho amafoto';

  @override
  String get manageAuctions => 'Gucunga Amasoko';

  @override
  String get searchAuctionLots => 'Shakisha amasoko, imodoka, cyangwa IDs...';

  @override
  String get deleteAuction => 'Siba Isoko';

  @override
  String deleteConfirmMessage(String name, String id) {
    return 'Siba \"$name\" (LOT #$id)?\n\nIbi bizasiba burundu iri soko n\'amafoto yaryo yose. Ibi ntibishobora gusubizwa.';
  }

  @override
  String get delete => 'SIBA';

  @override
  String get auctionDeleted => 'Isoko ryasibwe.';

  @override
  String get failedToLoadAuctions => 'Kuzana amasoko byaretse';

  @override
  String noAuctionsMatch(String query) {
    return 'Nta masoko ahuza na \"$query\"';
  }

  @override
  String noAuctionsYet(String filter) {
    return 'Nta masoko ya $filter nawe.';
  }

  @override
  String get viewBids => 'Reba Ibiciro';

  @override
  String get closeAuctionScreen => 'Funga Isoko';

  @override
  String get bidDetails => 'Ibisobanuro by\'Igiciro';

  @override
  String get noBidsForAuction => 'Nta biciro by\'iri soko nawe';

  @override
  String get clientManagement => 'GUCUNGA ABAKIRIYA';

  @override
  String get searchClients => 'Shakisha izina, ID, cyangwa imeli...';

  @override
  String get failedToLoadClients => 'Kuzana abakiriya byaretse';

  @override
  String get suspendClient => 'Gukumira Umukiriya';

  @override
  String get suspendClientMessage =>
      'Ibi bizabuza umukiriya gutanga ibiciro. Ushobora kumukoresha nanone igihe cyose.';

  @override
  String get suspend => 'KUMIRA';

  @override
  String get activateClient => 'Gukoresha Umukiriya';

  @override
  String get activateClientMessage =>
      'Ibi bizasubiza umukiriya uburenganzira bwose bwo gutanga ibiciro.';

  @override
  String get activate => 'KORESHA';

  @override
  String get clientSuspended => 'Umukiriya yakumirwa.';

  @override
  String get clientActivated => 'Umukiriya yakoreshetswagain.';

  @override
  String noClientsMatch(String query) {
    return 'Nta bakiriya bahuza na \"$query\"';
  }

  @override
  String noClientsYet(String filter) {
    return 'Nta bakiriya ba $filter.';
  }

  @override
  String get phone => 'TELEFONI';

  @override
  String get districtLabel => 'AKARERE';

  @override
  String get province => 'INTARA';

  @override
  String get lastLogin => 'INJIRA YA NYUMA';

  @override
  String get regionReports => 'Raporo z\'Akarere';

  @override
  String get generateReport => 'Kora Raporo';

  @override
  String get reportGenerated => 'Raporo yakorwe neza';

  @override
  String get failedToGenerateReport => 'Gukora raporo byaretse';

  @override
  String get downloadReport => 'Kurura Raporo';

  @override
  String get adminFeedback => 'Ibitekerezo by\'Abakiriya';

  @override
  String get noFeedbackYet => 'Nta bitekerezo byatanzwe nawe';

  @override
  String feedbackFrom(String name) {
    return 'Ibitekerezo bya $name';
  }

  @override
  String get editRegionAdmin => 'Hindura Umuyobozi w\'Akarere';

  @override
  String get addRegionAdmin => 'Ongeraho Umuyobozi w\'Akarere';

  @override
  String get adminInformation => 'AMAKURU Y\'UMUYOBOZI';

  @override
  String get temporaryPasswordNote =>
      'Ijambo ry\'ibanga ry\'agateganyo rizakorwa by\'ubwagira.';

  @override
  String get regionAssignment => 'GUHA AKARERE';

  @override
  String get regionCannotChange =>
      'Akarere ntishobora guhindurwa nyuma yo gukora.';

  @override
  String get permissions => 'UBURENGANZIRA';

  @override
  String get postAuctionsPermission => 'Gutangaza Amasoko';

  @override
  String get createNewLots => 'Gukora ibihe bishya by\'imodoka';

  @override
  String get manageClientsPermission => 'Gucunga Abakiriya';

  @override
  String get reviewBidderDocs => 'Gusuzuma inyandiko z\'abatanga ibiciro';

  @override
  String get viewReportsPermission => 'Reba Raporo';

  @override
  String get accessRegionalStats => 'Kugera ku mibare y\'akarere';

  @override
  String get closeAuctionsPermission => 'Gufunga Amasoko';

  @override
  String get manuallyCloseAndAward => 'Gufunga no guha igihembo';

  @override
  String get adminCreated => 'Umuyobozi Yaremwe';

  @override
  String adminCreatedFor(String name, String region) {
    return '$name yaremwe ku karere ka $region.';
  }

  @override
  String get temporaryPassword => 'Ijambo ry\'Ibanga ry\'Agateganyo';

  @override
  String get savePasswordWarning =>
      'Bika iryo jambo ry\'ibanga — ntishobora kubonerwa nyuma yo gufunga iyi dialogi.';

  @override
  String get done => 'Byarangiye';

  @override
  String get copyPassword => 'Kopi ijambo ry\'ibanga';

  @override
  String get passwordCopied => 'Ijambo ry\'ibanga ryakopishijwe';

  @override
  String get pleaseSelectRegion => 'Hitamo akarere';

  @override
  String creationFailed(String error) {
    return 'Gukora byaretse: $error';
  }

  @override
  String get adminUpdatedSuccess => 'Umuyobozi yahinduwe neza';

  @override
  String failedToUpdateAdmin(String error) {
    return 'Guhinduura umuyobozi byaretse: $error';
  }

  @override
  String get superAdminDashboard => 'UMUYOBOZI MUKURU';

  @override
  String get commissioner => 'Komiseri';

  @override
  String get superAdministrator => 'Umuyobozi Mukuru';

  @override
  String get nationalRevenue => 'UMUSARURO W\'IGIHUGU';

  @override
  String get totalCollectedAllTime => 'Byose Byakusanyijwe — Igihe Cyose';

  @override
  String closedAuctionsCount(int count) {
    return 'Amasoko $count yarangiye';
  }

  @override
  String get regionsOverview => 'Incamake y\'Intara';

  @override
  String get adminActivity => 'Ibikorwa by\'Abayobozi';

  @override
  String get quickActions => 'Ibikorwa Vuba';

  @override
  String get appSettings => 'Igenamiterere ry\'Porogaramu';

  @override
  String get nationalReports => 'Raporo z\'Igihugu';

  @override
  String get totalAuctions => 'AMASOKO YOSE';

  @override
  String get totalBidsLabel => 'IBICIRO BYOSE';

  @override
  String get clients => 'ABAKIRIYA';

  @override
  String get regionAdmins => 'ABAYOBOZI B\'INTARA';

  @override
  String get noRegionAdmins =>
      'Nta bayobozi b\'intara nawe.\nKanda + kugira ngo wongeraho umuyobozi wa mbere.';

  @override
  String get noAdminActivity => 'Nta bikorwa by\'abayobozi nawe';

  @override
  String get loadingRegions => 'Gutangira intara…';

  @override
  String auctionsCount(int count) {
    return 'Amasoko $count';
  }

  @override
  String regionLabel(String region) {
    return 'Akarere ka $region';
  }

  @override
  String get manageAdmins => 'Gucunga Abayobozi';

  @override
  String get searchAdmins => 'Shakisha abayobozi...';

  @override
  String noAdminsMatch(String query) {
    return 'Nta bayobozi bahuza na \"$query\"';
  }

  @override
  String get noAdminsYet => 'Nta bayobozi nawe';

  @override
  String get superAdminNav1 => 'IMBONERAHAMWE';

  @override
  String get superAdminNav2 => 'ABAYOBOZI';

  @override
  String get superAdminNav3 => 'RAPORO';

  @override
  String get superAdminNav4 => 'IGENAMITERERE';

  @override
  String get superAdminNav5 => 'UMWIRONDORO';

  @override
  String get feedbackTitle => 'Ibitekerezo';

  @override
  String get feedbackHeaderTitle => 'Ibitekerezo by\'E-CYAMUNARA';

  @override
  String get auctionFeedbackTitle => 'Ibitekerezo by\'Isoko\nry\'E-CYAMUNARA';

  @override
  String get helpImprove => 'Dufashe kunoza porogaramu yacu';

  @override
  String get helpImproveService => 'Dufashe kunoza serivisi yacu';

  @override
  String get rateExperience => 'Shyira Amanota ku Makumyabanga Yawe';

  @override
  String get howSatisfied => 'Ese urishimye porogaramu yacu kangahe?';

  @override
  String get howSatisfiedService => 'Ese urishimye serivisi yacu kangahe?';

  @override
  String get whatWentWell => 'Iki cyagenze neza?';

  @override
  String get additionalComments => 'Ibitekerezo Byiyongereye';

  @override
  String get shareExperience => 'Sangira makumyabanga yawe...';

  @override
  String get wouldRecommend => 'Ese uzashishikariza abandi E-CYAMUNARA?';

  @override
  String get yes => 'Yego';

  @override
  String get no => 'Oya';

  @override
  String get submitFeedback => 'OHEREZA IBITEKEREZO';

  @override
  String get thankYouFeedback => 'Urakoze ibitekerezo byawe!';

  @override
  String failedToSubmit(String error) {
    return 'Kohereza byaretse: $error';
  }

  @override
  String get thankYouRnp =>
      'Urakoze gufasha Rwanda National Police kunoza serivisi';

  @override
  String get indicateRecommend =>
      'Nyamuneka twereke niba uzashishikariza abandi';

  @override
  String get auctionItem => 'IGICURUZWA';

  @override
  String get date => 'ITARIKI';

  @override
  String get tagEasyToUse => 'Byoroshye Gukoresha';

  @override
  String get tagFastProcess => 'Inzira Yihuta';

  @override
  String get tagTransparency => 'Uburambe';

  @override
  String get tagCommunication => 'Itumanaho';

  @override
  String get tagPaymentFlow => 'Inzira yo Kwishyura';

  @override
  String get tagDocumentation => 'Inyandiko';

  @override
  String get ratingPoor => 'Nbi';

  @override
  String get ratingFair => 'Bisanzwe';

  @override
  String get ratingGood => 'Byiza';

  @override
  String get ratingVeryGood => 'Byiza Cyane';

  @override
  String get ratingExcellent => 'Nziza Cyane';

  @override
  String get validatorPhoneRequired => 'Nimero ya telefoni irakenewe';

  @override
  String get validatorPhoneInvalid =>
      'Injiza nimero ya telefoni y\'u Rwanda yemewe (urugero: 078XXXXXXX)';

  @override
  String get validatorNationalIdRequired => 'Indangamuntu irakenewe';

  @override
  String get validatorNationalIdLength => 'Indangamuntu igomba kuba imibare 16';

  @override
  String get validatorNationalIdDigitsOnly =>
      'Indangamuntu igomba kuba imibare gusa';

  @override
  String get validatorPasswordRequired => 'Ijambo ry\'ibanga rirakenewe';

  @override
  String get validatorPasswordTooShort =>
      'Ijambo ry\'ibanga rigomba kuba nibura inyuguti 8';

  @override
  String get validatorPasswordUppercase =>
      'Ongeraho nibura inyuguti imwe nkuru';

  @override
  String get validatorPasswordNumber => 'Ongeraho nibura inimero imwe';

  @override
  String get validatorPasswordSpecial =>
      'Ongeraho nibura ikimenyetso kimwe cyihariye (!@#\$%^&*)';

  @override
  String get validatorConfirmRequired =>
      'Nyamuneka emeza ijambo ry\'ibanga ryawe';

  @override
  String get validatorPasswordsNoMatch => 'Amagambo y\'ibanga ntahuza';

  @override
  String get validatorFullNameRequired => 'Amazina yombi arakenewe';

  @override
  String get validatorNameTooShort =>
      'Izina ni ngufi cyane (nibura inyuguti 3)';

  @override
  String get validatorBidRequired => 'Ingano y\'igiciro irakenewe';

  @override
  String get validatorBidInvalid => 'Injiza ingano yemewe';

  @override
  String get validatorBidZero => 'Igiciro kigomba kuba gifite agaciro';

  @override
  String validatorBidTooLow(String minimum) {
    return 'Igiciro kigomba kuba hejuru ya RWF $minimum';
  }

  @override
  String get validatorDescriptionRequired => 'Ibisobanuro birakenewe';

  @override
  String get validatorDescriptionTooShort =>
      'Ibisobanuro bigomba kuba nibura inyuguti 20';

  @override
  String get validatorCommentTooLong =>
      'Igitekerezo ntigomba kurenza inyuguti 250';

  @override
  String get validatorEndDateRequired => 'Itariki y\'iherezo irakenewe';

  @override
  String get validatorEndDateBeforeStart =>
      'Itariki y\'iherezo igomba kuba nyuma y\'iy\'intangiriro';

  @override
  String get validatorEndDatePast =>
      'Itariki y\'iherezo igomba kuba mu gihe kizaza';

  @override
  String get loading => 'Gutangira...';

  @override
  String get error => 'Ikosa';

  @override
  String get success => 'Byagenze Neza';

  @override
  String get confirm => 'Emeza';

  @override
  String get save => 'Bika';

  @override
  String get edit => 'Hindura';

  @override
  String get add => 'Ongeraho';

  @override
  String get create => 'Kora';

  @override
  String get update => 'Vugurura';

  @override
  String get search => 'Shakisha';

  @override
  String get filter => 'Shungura';

  @override
  String get refresh => 'Vugurura';

  @override
  String get back => 'Subira';

  @override
  String get next => 'Komeza';

  @override
  String get submit => 'Ohereza';

  @override
  String get superAdminBadge => 'UMUYOBOZI MUKURU';

  @override
  String get regionAdminBadge => 'UMUYOBOZI W\'AKARERE';

  @override
  String get pendingBadge => 'BIRITEGEREJWE';

  @override
  String get activeBadge => 'AKORA';

  @override
  String get offBadge => 'CYARETSE';

  @override
  String get adminProfile => 'Umwirondoro w\'Umuyobozi';

  @override
  String get postedStat => 'YASHYIZWE';

  @override
  String get closedStat => 'YARAFUNZWE';

  @override
  String get statusStat => 'IMIMERERE';

  @override
  String get roleLabel => 'INSHINGANO';

  @override
  String get accountStatusLabel => 'IMIMERERE Y\'KONTI';

  @override
  String get memberSince => 'UMUNSI W\'IYINJIRA';

  @override
  String get profileLoadError =>
      'Umwirondoro ntushobora kuvugururwa. Amateka ya nyuma ararabwa.';

  @override
  String get neverRecorded => 'Ntabwo byanditswe';

  @override
  String get fullNameEmpty => 'Amazina yuzuye arakenewe';

  @override
  String updateFailed(String error) {
    return 'Guhindura byanze: $error';
  }

  @override
  String passwordChangeFailed(String error) {
    return 'Guhindura ijambo banga byanze: $error';
  }

  @override
  String get updatePasswordDesc => 'Vugurura ijambo banga rya konti yawe';

  @override
  String get selectLanguage => 'Hitamo Ururimi';

  @override
  String get failedToLoadAdmins => 'Gushyikira abayobozi byanze';

  @override
  String get tapToViewDetails => 'Kanda kugira ngo ubone amakuru';

  @override
  String get notOnRecord => 'Ntibanditswe';

  @override
  String get addNewAdmin => 'Ongeraho umuyobozi mushya';

  @override
  String get suspendAdmin => 'Hagarika Umuyobozi';

  @override
  String suspendAdminMessage(String name, String region) {
    return 'Hagarika $name ($region)?\n\nBazavaho ako kanya kandi ntibashobore kwinjira kugeza bazasubizwa.';
  }

  @override
  String get activateAdmin => 'Subiza Umuyobozi';

  @override
  String activateAdminMessage(String name, String region) {
    return 'Subiza $name ($region)?\n\nBazashobora kwinjira ako kanya.';
  }

  @override
  String adminSuspendedMsg(String name) {
    return '$name yahagaritswe';
  }

  @override
  String adminActivatedMsg(String name) {
    return '$name yasubizwa';
  }

  @override
  String get sessionExpiredError => 'Igihe cyarangiye — injira nanone';

  @override
  String get createAdmin => 'SHIRAHO UMUYOBOZI';

  @override
  String get fiscalPerformance => 'IMIKORERE Y\'IMARI';

  @override
  String get nationwideLedger => 'Igitabo cy\'Igihugu';

  @override
  String get totalRevenue => 'INYUNGU ZOSE';

  @override
  String get auctionsLabel => 'AMATANGWA';

  @override
  String get bidsLabel => 'AMAPROPOSITION';

  @override
  String get performanceByRegion => 'Imikorere ku Ntara';

  @override
  String get failedToLoadRegionData => 'Gushyikira amakuru y\'intara byanze';

  @override
  String get noAuctionDataForPeriod => 'Nta makuru y\'amatangwa muri iki gihe';

  @override
  String get reportReady => 'Raporo Iteguwe';

  @override
  String get reportCopyLinkInstruction =>
      'Kopi aho lien hasi haskii ubufunguke muri browser yawe:';

  @override
  String get reportLinkValidity => 'Umuyoboro urakora iminsi 7.';

  @override
  String get copyUrl => 'Kopi URL';

  @override
  String get urlCopied => 'URL yakopiwemo mu clipboard';

  @override
  String get reportReadyNoUrl =>
      'Raporo yagenewe ariko nta URL yo kurura yabonetse';

  @override
  String downloadFailed(String error) {
    return 'Kurura byanze: $error';
  }

  @override
  String get superAdminProfile => 'Umwirondoro w\'Umuyobozi Mukuru';

  @override
  String get adminsBadge => 'ABAYOBOZI';

  @override
  String get regionsCount => 'INTARA';

  @override
  String get systemAccess => 'UBURENGANZIRA BWA SISITEMU';

  @override
  String get manageRegionAdminsPermission => 'Gucunga Abayobozi b\'Intara';

  @override
  String get viewAllRegionsPermission => 'Kureba Intara Zose';

  @override
  String get systemConfigPermission => 'Igenamiterere rya Sisitemu';

  @override
  String get auditLogsPermission => 'Inzira z\'Ubugenzuzi';

  @override
  String get authorityLabel => 'UBUBASHA';

  @override
  String get nationalLevelRnp => 'Urwego rw\'Igihugu — RNP';

  @override
  String get basicInformation => 'AMAKURU ASANZWE';

  @override
  String get technicalSpecs => 'IBISOBANURO BY\'IMYIRONDORO';

  @override
  String get ownershipSection => 'UBUTENGANYI N\'AMATEKA';

  @override
  String get mainCategoryLabel => 'UBWOKO BUKURU';

  @override
  String get subCategoryLabel => 'UBWOKO BUNINI';

  @override
  String get brandLabel => 'MAKA';

  @override
  String get modelField => 'MODELI';

  @override
  String get manufacturingYearLabel => 'UMWAKA W\'UBUREMANE';

  @override
  String get colorField => 'IBARA';

  @override
  String get mileageField => 'KILOMETERI ZAGENZE';

  @override
  String get fuelTypeField => 'UBWOKO BW\'INKORANA';

  @override
  String get transmissionField => 'INGIRISHI';

  @override
  String get engineSizeField => 'INGANO YA MOTERI (L)';

  @override
  String get engineCcField => 'CC YA MOTERI';

  @override
  String get drivetrainField => 'UBURYO BUGUKANDAGIRA';

  @override
  String get seatingCapacityField => 'IMYANYA YO KWICARA';

  @override
  String get frameMaterialField => 'IBIKORESHO BY\'INZIZI';

  @override
  String get gearCountField => 'UMUBARE W\'INGIRISHI';

  @override
  String get suspensionTypeField => 'UBWOKO BW\'INZIRA';

  @override
  String get brakeTypeField => 'UBWOKO BW\'AMAFARASHI';

  @override
  String get ownershipHistoryField => 'AMATEKA Y\'UBUTENGANYI';

  @override
  String get accidentHistoryField => 'AMATEKA Y\'IMPANUKA';

  @override
  String get insuranceStatusField => 'IMIMERERE Y\'UBWISHINGIZI';

  @override
  String get optionPetrol => 'Benzini';

  @override
  String get optionDiesel => 'Mazutu';

  @override
  String get optionHybrid => 'Hybrid';

  @override
  String get optionElectric => 'Amashanyarazi';

  @override
  String get optionAutomatic => 'Otomatike';

  @override
  String get optionManual => 'Maniyeli';

  @override
  String get optionCvt => 'CVT';

  @override
  String get optionExcellent => 'Byiza cyane';

  @override
  String get optionVeryGood => 'Byiza';

  @override
  String get optionGood => 'Bifatika';

  @override
  String get optionFair => 'Bisanzwe';

  @override
  String get optionPoor => 'Bibi';

  @override
  String get optionFirstOwner => 'Nyir\'wibanze';

  @override
  String get optionSecondOwner => 'Nyir\'inshuro ya kabiri';

  @override
  String get optionThirdOwner => 'Nyir\'inshuro ya gatatu';

  @override
  String get optionFleetVehicle => 'Imodoka ya Filote';

  @override
  String get optionInsured => 'Ifite ubwishingizi';

  @override
  String get optionExpiredInsurance => 'Ubwishingizi bwarangiye';

  @override
  String get optionNeverInsured => 'Ntabwo yigeze ifata ubwishingizi';

  @override
  String get optionUnknown => 'Ntizwi';

  @override
  String get optionNoAccidents => 'Nta mpanuka';

  @override
  String get optionMinorDamage => 'Ingaruka nto';

  @override
  String get optionMajorDamage => 'Ingaruka nini';

  @override
  String validatorYearRange(int year) {
    return 'Umwaka ugomba kuba hagati ya 1900 na $year';
  }

  @override
  String get validatorMileageNegative =>
      'Kilometeri ntishobora kuba nke y\'ubusa';

  @override
  String get validatorEngineCcRequired => 'CC ya moteri birakenewe ku moto';

  @override
  String get validatorEngineSizeRequired =>
      'Ingano ya moteri birakenewe ku modoka';

  @override
  String get validatorTransmissionRequired => 'Ingirishi birakenewe ku modoka';

  @override
  String get validatorGearCountRequired =>
      'Umubare w\'ingirishi birakenewe ku igare';

  @override
  String get validatorFuelTypeRequired => 'Ubwoko bw\'inkorana burakenewe';

  @override
  String get validatorSubCategoryRequired => 'Ubwoko bunini burakenewe';

  @override
  String get validatorBrandRequired => 'Maka irakenewe';

  @override
  String get validatorModelRequired => 'Izina rya modeli rirakenewe';

  @override
  String get validatorColorRequired => 'Ibara birakenewe';

  @override
  String get validatorYearRequired => 'Umwaka w\'uburemane urakenewe';

  @override
  String get validatorMileageRequired => 'Kilometeri zagenze zirakenewe';

  @override
  String get selectSubCategory => 'Hitamo ubwoko bunini';

  @override
  String get selectBrand => 'Hitamo maka';

  @override
  String get selectFuelType => 'Hitamo ubwoko bw\'inkorana';

  @override
  String get selectTransmission => 'Hitamo ingirishi';

  @override
  String get selectDrivetrain => 'Hitamo uburyo bugukandagira';

  @override
  String get selectCondition => 'Hitamo imimerere';

  @override
  String get selectFrameMaterial => 'Hitamo ibikoresho by\'inzizi';

  @override
  String get selectSuspension => 'Hitamo ubwoko bw\'inzira';

  @override
  String get selectBrakeType => 'Hitamo ubwoko bw\'amafarashi';

  @override
  String get selectOwnershipHistory => 'Hitamo amateka y\'ubutenganyi';

  @override
  String get selectAccidentHistory => 'Hitamo amateka y\'impanuka';

  @override
  String get selectInsuranceStatus => 'Hitamo imimerere y\'ubwishingizi';

  @override
  String get vehicleLabel => 'Imodoka';

  @override
  String get motorcycleLabel => 'Moto';

  @override
  String get bicycleLabel => 'Igare';

  @override
  String brandSubcategoryChip(String brand, String subcategory) {
    return '$brand • $subcategory';
  }

  @override
  String get publishDraft => 'Tangaza Isoko';

  @override
  String get publish => 'TANGAZA';

  @override
  String get publishTooltip => 'Tangaza Inzibacyuho';

  @override
  String publishConfirmMessage(String name, String id) {
    return 'Tangaza "$name" (LOT #$id)?\n\nIbi bizatera isoko kugaragara kuri bakiriya bose. Gutanga ibiciro bizatangira ako kanya.';
  }

  @override
  String get auctionPublished => 'Isoko ryatangazwa neza!';

  @override
  String get auctionSoftDeleted => 'Isoko ryavanwe ku rutonde (amateka y\'ibiciro abitswe).';
}
