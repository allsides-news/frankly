import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_zh.dart';

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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('es'),
    Locale('zh'),
    Locale.fromSubtags(
        languageCode: 'zh', countryCode: 'TW', scriptCode: 'Hant')
  ];

  /// No description provided for @aVIssues.
  ///
  /// In en, this message translates to:
  /// **'A/V issues?'**
  String get aVIssues;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutSectionBrandName.
  ///
  /// In en, this message translates to:
  /// **'AllSides Roundtables'**
  String get aboutSectionBrandName;

  /// No description provided for @aboutSectionClosing.
  ///
  /// In en, this message translates to:
  /// **'.'**
  String get aboutSectionClosing;

  /// No description provided for @aboutSectionDialogueGuides.
  ///
  /// In en, this message translates to:
  /// **'. Dialogue guides are adapted from '**
  String get aboutSectionDialogueGuides;

  /// No description provided for @aboutSectionPoweredBy.
  ///
  /// In en, this message translates to:
  /// **'This platform is powered by '**
  String get aboutSectionPoweredBy;

  /// No description provided for @aboutSectionTagline.
  ///
  /// In en, this message translates to:
  /// **'matches you with diverse discussion groups to build mutual understanding through guided conversations.'**
  String get aboutSectionTagline;

  /// No description provided for @aboutUs.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutUs;

  /// No description provided for @accountExistsWithSameEmail.
  ///
  /// In en, this message translates to:
  /// **'An account exists with the same email address but a different sign in method. Use Sign in with Email and click Forgot Password if you don\'t know it. Or, Sign Up again using a different email.'**
  String get accountExistsWithSameEmail;

  /// No description provided for @addACategory.
  ///
  /// In en, this message translates to:
  /// **'Add a category'**
  String get addACategory;

  /// No description provided for @addAPrerequisiteTemplate.
  ///
  /// In en, this message translates to:
  /// **'Add a prerequisite template'**
  String get addAPrerequisiteTemplate;

  /// No description provided for @addAQuestion.
  ///
  /// In en, this message translates to:
  /// **'Add a question'**
  String get addAQuestion;

  /// No description provided for @addActionLink.
  ///
  /// In en, this message translates to:
  /// **'Add action link'**
  String get addActionLink;

  /// No description provided for @addAgendaItem.
  ///
  /// In en, this message translates to:
  /// **'Add agenda item'**
  String get addAgendaItem;

  /// No description provided for @addCategory.
  ///
  /// In en, this message translates to:
  /// **'Add a category'**
  String get addCategory;

  /// No description provided for @addComment.
  ///
  /// In en, this message translates to:
  /// **'Add comment'**
  String get addComment;

  /// No description provided for @addCommunityImages.
  ///
  /// In en, this message translates to:
  /// **'Add space images'**
  String get addCommunityImages;

  /// No description provided for @addNew.
  ///
  /// In en, this message translates to:
  /// **'+ Add New'**
  String get addNew;

  /// No description provided for @addOption.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get addOption;

  /// No description provided for @addPrerequisiteTemplate.
  ///
  /// In en, this message translates to:
  /// **'Add a prerequisite template'**
  String get addPrerequisiteTemplate;

  /// No description provided for @addQuestion.
  ///
  /// In en, this message translates to:
  /// **'Add a question'**
  String get addQuestion;

  /// No description provided for @addSomethingHere.
  ///
  /// In en, this message translates to:
  /// **'Add something here'**
  String get addSomethingHere;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @agreeAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Agree and continue'**
  String get agreeAndContinue;

  /// No description provided for @alreadyUserSignIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyUserSignIn;

  /// No description provided for @notUserSignUp.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get notUserSignUp;

  /// No description provided for @anonymous.
  ///
  /// In en, this message translates to:
  /// **'Anonymous'**
  String get anonymous;

  /// No description provided for @appDescription.
  ///
  /// In en, this message translates to:
  /// **'An online deliberations platform'**
  String get appDescription;

  /// No description provided for @appNameHome.
  ///
  /// In en, this message translates to:
  /// **'{appName} - Home'**
  String appNameHome(Object appName);

  /// No description provided for @appNameTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'{appName} Terms of Service'**
  String appNameTermsOfService(Object appName);

  /// No description provided for @appNameTitle.
  ///
  /// In en, this message translates to:
  /// **'{appName}'**
  String appNameTitle(Object appName);

  /// No description provided for @appNameUnsubscribe.
  ///
  /// In en, this message translates to:
  /// **'{appName} - Unsubscribe'**
  String appNameUnsubscribe(Object appName);

  /// No description provided for @appNameUserSettings.
  ///
  /// In en, this message translates to:
  /// **'{appName} - User Settings'**
  String appNameUserSettings(Object appName);

  /// No description provided for @appNameWelcome.
  ///
  /// In en, this message translates to:
  /// **'{appName} - Welcome'**
  String appNameWelcome(Object appName);

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'AllSides Roundtables'**
  String get appTitle;

  /// No description provided for @appTitleHome.
  ///
  /// In en, this message translates to:
  /// **'{appName} - Home'**
  String appTitleHome(Object appName);

  /// No description provided for @appTitleUnsubscribe.
  ///
  /// In en, this message translates to:
  /// **'{appName} - Unsubscribe'**
  String appTitleUnsubscribe(Object appName);

  /// No description provided for @appTitleUserSettings.
  ///
  /// In en, this message translates to:
  /// **'{appName} - User Settings'**
  String appTitleUserSettings(Object appName);

  /// No description provided for @appTitleWelcome.
  ///
  /// In en, this message translates to:
  /// **'{appName} - Welcome'**
  String appTitleWelcome(Object appName);

  /// No description provided for @areYouSureYouWantToDeleteMedia.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete media?'**
  String get areYouSureYouWantToDeleteMedia;

  /// No description provided for @areYouSureYouWantToRefreshTheGuide.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to refresh the guide?'**
  String get areYouSureYouWantToRefreshTheGuide;

  /// No description provided for @aspectRatioClipped.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio clipped'**
  String get aspectRatioClipped;

  /// No description provided for @attendee.
  ///
  /// In en, this message translates to:
  /// **'Attendee'**
  String get attendee;

  /// No description provided for @audioInputDevice.
  ///
  /// In en, this message translates to:
  /// **'Audio Input Device:'**
  String get audioInputDevice;

  /// No description provided for @avIssues.
  ///
  /// In en, this message translates to:
  /// **'A/V issues?'**
  String get avIssues;

  /// No description provided for @avErrorDuplicateIdentity.
  ///
  /// In en, this message translates to:
  /// **'You are already connected from another device or browser.'**
  String get avErrorDuplicateIdentity;

  /// No description provided for @avErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Audio/video devices not found.'**
  String get avErrorNotFound;

  /// No description provided for @avErrorMediaAccess.
  ///
  /// In en, this message translates to:
  /// **'Unable to access media devices.'**
  String get avErrorMediaAccess;

  /// No description provided for @avErrorPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Permission to use audio/video devices is required.'**
  String get avErrorPermissionRequired;

  /// No description provided for @avErrorListenOnly.
  ///
  /// In en, this message translates to:
  /// **'Camera or microphone isn\'t available. You can still join and listen.'**
  String get avErrorListenOnly;

  /// No description provided for @avErrorJoinWithoutDevices.
  ///
  /// In en, this message translates to:
  /// **'Join without camera or microphone'**
  String get avErrorJoinWithoutDevices;

  /// No description provided for @avErrorDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Audio/video devices disconnected.'**
  String get avErrorDisconnected;

  /// No description provided for @avErrorConstraints.
  ///
  /// In en, this message translates to:
  /// **'Media constraints error.'**
  String get avErrorConstraints;

  /// No description provided for @avErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error with audio/video connection.'**
  String get avErrorNetwork;

  /// No description provided for @avErrorNotReadable.
  ///
  /// In en, this message translates to:
  /// **'Audio/video device can\'t be read or is busy.'**
  String get avErrorNotReadable;

  /// No description provided for @awaitingResponses.
  ///
  /// In en, this message translates to:
  /// **'Awaiting responses…'**
  String get awaitingResponses;

  /// No description provided for @banned.
  ///
  /// In en, this message translates to:
  /// **'Banned'**
  String get banned;

  /// No description provided for @brandYourSpace.
  ///
  /// In en, this message translates to:
  /// **'Brand your space'**
  String get brandYourSpace;

  /// No description provided for @broadcast.
  ///
  /// In en, this message translates to:
  /// **'Broadcast'**
  String get broadcast;

  /// No description provided for @buildCommunitySpace.
  ///
  /// In en, this message translates to:
  /// **'Build your space'**
  String get buildCommunitySpace;

  /// No description provided for @buildYourCommunitySpace.
  ///
  /// In en, this message translates to:
  /// **'Build your space'**
  String get buildYourCommunitySpace;

  /// No description provided for @byCategory.
  ///
  /// In en, this message translates to:
  /// **'By Category'**
  String get byCategory;

  /// No description provided for @bySigningInRegisteringOrUsing.
  ///
  /// In en, this message translates to:
  /// **'By signing in, registering, or using {appName}, I agree to be bound by the '**
  String bySigningInRegisteringOrUsing(Object appName);

  /// No description provided for @bySize.
  ///
  /// In en, this message translates to:
  /// **'By Size'**
  String get bySize;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cancelCurrentPlan.
  ///
  /// In en, this message translates to:
  /// **'Cancel current plan?'**
  String get cancelCurrentPlan;

  /// No description provided for @cancelEvent.
  ///
  /// In en, this message translates to:
  /// **'Cancel Event'**
  String get cancelEvent;

  /// No description provided for @cancelParticipation.
  ///
  /// In en, this message translates to:
  /// **'Cancel Participation'**
  String get cancelParticipation;

  /// No description provided for @cannotPlayVimeoVideo.
  ///
  /// In en, this message translates to:
  /// **'Cannot play Vimeo video'**
  String get cannotPlayVimeoVideo;

  /// No description provided for @cannotPlayYouTubeVideo.
  ///
  /// In en, this message translates to:
  /// **'Cannot play YouTube video'**
  String get cannotPlayYouTubeVideo;

  /// No description provided for @cannotPlayYoutubeVideo.
  ///
  /// In en, this message translates to:
  /// **'Cannot play YouTube video'**
  String get cannotPlayYoutubeVideo;

  /// No description provided for @changeLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get changeLanguage;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @chatMessage.
  ///
  /// In en, this message translates to:
  /// **'Chat Message'**
  String get chatMessage;

  /// No description provided for @chatWithParticipants.
  ///
  /// In en, this message translates to:
  /// **'Chat with participants'**
  String get chatWithParticipants;

  /// No description provided for @clearAgenda.
  ///
  /// In en, this message translates to:
  /// **'Clear agenda?'**
  String get clearAgenda;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @closeEdit.
  ///
  /// In en, this message translates to:
  /// **'Close Edit'**
  String get closeEdit;

  /// No description provided for @communitySuccessPrefix.
  ///
  /// In en, this message translates to:
  /// **'You’ve successfully created your space'**
  String get communitySuccessPrefix;

  /// No description provided for @communitySuccessSuffix.
  ///
  /// In en, this message translates to:
  /// **'Click the pencil icon in the top right to edit your space settings.'**
  String get communitySuccessSuffix;

  /// No description provided for @congratulations.
  ///
  /// In en, this message translates to:
  /// **'Congratulations!'**
  String get congratulations;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete?'**
  String get confirmDelete;

  /// No description provided for @confirmDeleteMedia.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete media?'**
  String get confirmDeleteMedia;

  /// No description provided for @confirmRefreshGuide.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to refresh the guide?'**
  String get confirmRefreshGuide;

  /// No description provided for @contactEmail.
  ///
  /// In en, this message translates to:
  /// **'Contact email'**
  String get contactEmail;

  /// No description provided for @couldntFindAccount.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t find an account with this email. Try '**
  String get couldntFindAccount;

  /// No description provided for @createAPost.
  ///
  /// In en, this message translates to:
  /// **'Create a post'**
  String get createAPost;

  /// No description provided for @createAResource.
  ///
  /// In en, this message translates to:
  /// **'Create a resource'**
  String get createAResource;

  /// No description provided for @createATemplate.
  ///
  /// In en, this message translates to:
  /// **'Create a template'**
  String get createATemplate;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get createAccount;

  /// No description provided for @createAnAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'Create an announcement'**
  String get createAnAnnouncement;

  /// No description provided for @createAnEvent.
  ///
  /// In en, this message translates to:
  /// **'Create an event'**
  String get createAnEvent;

  /// No description provided for @createEvent.
  ///
  /// In en, this message translates to:
  /// **'Create Event'**
  String get createEvent;

  /// No description provided for @createACommunity.
  ///
  /// In en, this message translates to:
  /// **'Create a Space'**
  String get createACommunity;

  /// No description provided for @currentParticipants.
  ///
  /// In en, this message translates to:
  /// **'Current\nParticipants'**
  String get currentParticipants;

  /// No description provided for @darkColorHex.
  ///
  /// In en, this message translates to:
  /// **'Dark Color HEX#'**
  String get darkColorHex;

  /// No description provided for @defineBreakoutsOptional.
  ///
  /// In en, this message translates to:
  /// **'Define Breakouts (Optional)'**
  String get defineBreakoutsOptional;

  /// No description provided for @deleteAgendaItem.
  ///
  /// In en, this message translates to:
  /// **'Delete {title} agenda item'**
  String deleteAgendaItem(Object title);

  /// No description provided for @deleteAgendaItemGeneral.
  ///
  /// In en, this message translates to:
  /// **'Delete agenda item'**
  String get deleteAgendaItemGeneral;

  /// No description provided for @deleteAgendaItemName.
  ///
  /// In en, this message translates to:
  /// **'Delete {itemName} agenda item'**
  String deleteAgendaItemName(Object itemName);

  /// No description provided for @roomNumber.
  ///
  /// In en, this message translates to:
  /// **'Room Number'**
  String get roomNumber;

  /// No description provided for @enterRoomNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter room number'**
  String get enterRoomNumber;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @confirmRemoveParticipant.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove {name} from this event?'**
  String confirmRemoveParticipant(Object name);

  /// No description provided for @thisUser.
  ///
  /// In en, this message translates to:
  /// **'this user'**
  String get thisUser;

  /// No description provided for @reassign.
  ///
  /// In en, this message translates to:
  /// **'Reassign'**
  String get reassign;

  /// No description provided for @fakeParticipantCount.
  ///
  /// In en, this message translates to:
  /// **'Fake Participant Count'**
  String get fakeParticipantCount;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @hideAgendaItem.
  ///
  /// In en, this message translates to:
  /// **'Hide agenda item'**
  String get hideAgendaItem;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @deleteComment.
  ///
  /// In en, this message translates to:
  /// **'Delete Comment'**
  String get deleteComment;

  /// No description provided for @deleteOption.
  ///
  /// In en, this message translates to:
  /// **'Delete option'**
  String get deleteOption;

  /// No description provided for @deletePost.
  ///
  /// In en, this message translates to:
  /// **'Delete post'**
  String get deletePost;

  /// No description provided for @deletePrerequisiteTemplate.
  ///
  /// In en, this message translates to:
  /// **'Delete prerequisite template'**
  String get deletePrerequisiteTemplate;

  /// No description provided for @deleteTitleAgendaItem.
  ///
  /// In en, this message translates to:
  /// **'Delete \$title agenda item'**
  String get deleteTitleAgendaItem;

  /// No description provided for @downloadMembersData.
  ///
  /// In en, this message translates to:
  /// **'Download members data'**
  String get downloadMembersData;

  /// No description provided for @duplicateItem.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Item'**
  String get duplicateItem;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @editImage.
  ///
  /// In en, this message translates to:
  /// **'Edit Image'**
  String get editImage;

  /// No description provided for @editItem.
  ///
  /// In en, this message translates to:
  /// **'Edit Item'**
  String get editItem;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @emailAddressAlreadyInUse.
  ///
  /// In en, this message translates to:
  /// **'You already created an account tied to this email address. Use Sign in with Email and click Forgot Password if you don\'t know it. Or, Sign Up again using a different email.'**
  String get emailAddressAlreadyInUse;

  /// No description provided for @emailAddressAlreadyInUseLoginError.
  ///
  /// In en, this message translates to:
  /// **'This email is already in use. Try '**
  String get emailAddressAlreadyInUseLoginError;

  /// No description provided for @endBreakoutRooms.
  ///
  /// In en, this message translates to:
  /// **'End Breakout Rooms'**
  String get endBreakoutRooms;

  /// No description provided for @enterValidName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid name'**
  String get enterValidName;

  /// No description provided for @endTime.
  ///
  /// In en, this message translates to:
  /// **'End Time'**
  String get endTime;

  /// No description provided for @enterHeadline.
  ///
  /// In en, this message translates to:
  /// **'Enter Headline'**
  String get enterHeadline;

  /// No description provided for @enterImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter Image title'**
  String get enterImageTitle;

  /// No description provided for @enterQuestionWithNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter Question {number}'**
  String enterQuestionWithNumber(Object number);

  /// No description provided for @enterVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter Video title'**
  String get enterVideoTitle;

  /// No description provided for @enterWaitingRoomText.
  ///
  /// In en, this message translates to:
  /// **'Enter waiting room text (optional)'**
  String get enterWaitingRoomText;

  /// No description provided for @enterWaitingRoomTextOptional.
  ///
  /// In en, this message translates to:
  /// **'Enter waiting room text (optional)'**
  String get enterWaitingRoomTextOptional;

  /// No description provided for @enterWordCloudPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter Word Cloud prompt'**
  String get enterWordCloudPrompt;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'Or'**
  String get or;

  /// No description provided for @errorLoadingCommunities.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong loading spaces. Please refresh.'**
  String get errorLoadingCommunities;

  /// No description provided for @errorLoadingEmail.
  ///
  /// In en, this message translates to:
  /// **'Error loading email.'**
  String get errorLoadingEmail;

  /// No description provided for @errorLoadingMemberships.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong loading memberships. Please refresh.'**
  String get errorLoadingMemberships;

  /// No description provided for @errorLoadingProfileInfo.
  ///
  /// In en, this message translates to:
  /// **'There was an error loading profile info.'**
  String get errorLoadingProfileInfo;

  /// No description provided for @errorOccurred.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get errorOccurred;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @eventDescription.
  ///
  /// In en, this message translates to:
  /// **'Event Description'**
  String get eventDescription;

  /// No description provided for @eventDetails.
  ///
  /// In en, this message translates to:
  /// **'Event Details'**
  String get eventDetails;

  /// No description provided for @eventIsLocked.
  ///
  /// In en, this message translates to:
  /// **'This event is locked'**
  String get eventIsLocked;

  /// No description provided for @ended.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get ended;

  /// No description provided for @eventHasEnded.
  ///
  /// In en, this message translates to:
  /// **'This meeting has ended'**
  String get eventHasEnded;

  /// No description provided for @eventLocked.
  ///
  /// In en, this message translates to:
  /// **'This event is locked'**
  String get eventLocked;

  /// No description provided for @eventTabsContent.
  ///
  /// In en, this message translates to:
  /// **'event-tabs-content'**
  String get eventTabsContent;

  /// No description provided for @eventTitle.
  ///
  /// In en, this message translates to:
  /// **'Event Title'**
  String get eventTitle;

  /// No description provided for @events.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get events;

  /// No description provided for @ex2.
  ///
  /// In en, this message translates to:
  /// **'Ex: 2'**
  String get ex2;

  /// No description provided for @exTwo.
  ///
  /// In en, this message translates to:
  /// **'Ex: 2'**
  String get exTwo;

  /// No description provided for @facebookUrl.
  ///
  /// In en, this message translates to:
  /// **'Facebook URL'**
  String get facebookUrl;

  /// No description provided for @facilitator.
  ///
  /// In en, this message translates to:
  /// **'Facilitator'**
  String get facilitator;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'filter'**
  String get filter;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @getCustomColors.
  ///
  /// In en, this message translates to:
  /// **'Get custom colors '**
  String get getCustomColors;

  /// No description provided for @googleMeet.
  ///
  /// In en, this message translates to:
  /// **'Google Meet'**
  String get googleMeet;

  /// No description provided for @hosted.
  ///
  /// In en, this message translates to:
  /// **'Hosted'**
  String get hosted;

  /// No description provided for @hostless.
  ///
  /// In en, this message translates to:
  /// **'Hostless'**
  String get hostless;

  /// No description provided for @iAgreeToThe.
  ///
  /// In en, this message translates to:
  /// **'I agree to the '**
  String get iAgreeToThe;

  /// No description provided for @imageUrlIsNotSet.
  ///
  /// In en, this message translates to:
  /// **'(Image URL is not set.)'**
  String get imageUrlIsNotSet;

  /// No description provided for @imageUrlNotSet.
  ///
  /// In en, this message translates to:
  /// **'(Image URL is not set.)'**
  String get imageUrlNotSet;

  /// No description provided for @instagramUrl.
  ///
  /// In en, this message translates to:
  /// **'Instagram URL'**
  String get instagramUrl;

  /// No description provided for @instantMeeting.
  ///
  /// In en, this message translates to:
  /// **'Instant Meeting'**
  String get instantMeeting;

  /// No description provided for @insteadSuffix.
  ///
  /// In en, this message translates to:
  /// **' instead.'**
  String get insteadSuffix;

  /// No description provided for @introductionContent.
  ///
  /// In en, this message translates to:
  /// **'_Introduce yourselves!  Each take one minute to answer one of the following questions._\n\n* What\'s something you did recently that was a lot of fun?\n* Who is your favorite cartoon character and why?\n* What\'s one thing you wish to accomplish before you die?\n* What movie did you NOT like?\n'**
  String get introductionContent;

  /// No description provided for @introductions.
  ///
  /// In en, this message translates to:
  /// **'Introductions'**
  String get introductions;

  /// No description provided for @joinCommunity.
  ///
  /// In en, this message translates to:
  /// **'Join {communityName}?'**
  String joinCommunity(Object communityName);

  /// No description provided for @joinEvent.
  ///
  /// In en, this message translates to:
  /// **'Join Event'**
  String get joinEvent;

  /// No description provided for @kickOutUser.
  ///
  /// In en, this message translates to:
  /// **'Kick out {displayName}?'**
  String kickOutUser(Object displayName);

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSelector.
  ///
  /// In en, this message translates to:
  /// **'Language Selector'**
  String get languageSelector;

  /// No description provided for @lastSession.
  ///
  /// In en, this message translates to:
  /// **'Last session'**
  String get lastSession;

  /// No description provided for @learnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn more'**
  String get learnMore;

  /// No description provided for @lightColorHex.
  ///
  /// In en, this message translates to:
  /// **'Light Color HEX#'**
  String get lightColorHex;

  /// No description provided for @linkedinUrl.
  ///
  /// In en, this message translates to:
  /// **'LinkedIn URL'**
  String get linkedinUrl;

  /// No description provided for @livestream.
  ///
  /// In en, this message translates to:
  /// **'Livestream'**
  String get livestream;

  /// No description provided for @locked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get locked;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @loggingIn.
  ///
  /// In en, this message translates to:
  /// **'logging in'**
  String get loggingIn;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @loopVideo.
  ///
  /// In en, this message translates to:
  /// **'Loop Video'**
  String get loopVideo;

  /// No description provided for @makeASuggestion.
  ///
  /// In en, this message translates to:
  /// **'Make a suggestion'**
  String get makeASuggestion;

  /// No description provided for @manageJoinRequests.
  ///
  /// In en, this message translates to:
  /// **'Manage Join Requests ({count})'**
  String manageJoinRequests(int count);

  /// No description provided for @maps.
  ///
  /// In en, this message translates to:
  /// **'Maps'**
  String get maps;

  /// No description provided for @matchingOptions.
  ///
  /// In en, this message translates to:
  /// **'Matching Options'**
  String get matchingOptions;

  /// No description provided for @matchingQuestions.
  ///
  /// In en, this message translates to:
  /// **'Matching questions'**
  String get matchingQuestions;

  /// No description provided for @maximum.
  ///
  /// In en, this message translates to:
  /// **'Maximum'**
  String get maximum;

  /// No description provided for @meetingGuideCard.
  ///
  /// In en, this message translates to:
  /// **'meeting-guide-card'**
  String get meetingGuideCard;

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @memberships.
  ///
  /// In en, this message translates to:
  /// **'memberships'**
  String get memberships;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @messageFrom.
  ///
  /// In en, this message translates to:
  /// **'Message from'**
  String get messageFrom;

  /// No description provided for @messageParticipants.
  ///
  /// In en, this message translates to:
  /// **'Message Participants'**
  String get messageParticipants;

  /// No description provided for @messageTime.
  ///
  /// In en, this message translates to:
  /// **'Message time'**
  String get messageTime;

  /// No description provided for @microsoftTeams.
  ///
  /// In en, this message translates to:
  /// **'Microsoft Teams'**
  String get microsoftTeams;

  /// No description provided for @mins.
  ///
  /// In en, this message translates to:
  /// **'mins'**
  String get mins;

  /// No description provided for @miscellaneous.
  ///
  /// In en, this message translates to:
  /// **'Miscellaneous'**
  String get miscellaneous;

  /// No description provided for @moderator.
  ///
  /// In en, this message translates to:
  /// **'Moderator'**
  String get moderator;

  /// No description provided for @mustBeLoggedInToAccessThisSection.
  ///
  /// In en, this message translates to:
  /// **'Must be logged in to access this section'**
  String get mustBeLoggedInToAccessThisSection;

  /// No description provided for @myCustomEvent.
  ///
  /// In en, this message translates to:
  /// **'My Custom Event'**
  String get myCustomEvent;

  /// No description provided for @myEvents.
  ///
  /// In en, this message translates to:
  /// **'My Events'**
  String get myEvents;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfile;

  /// No description provided for @myResponses.
  ///
  /// In en, this message translates to:
  /// **'My Responses'**
  String get myResponses;

  /// No description provided for @myUpcomingEvents.
  ///
  /// In en, this message translates to:
  /// **'My Upcoming Events'**
  String get myUpcomingEvents;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @newAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'New Announcement'**
  String get newAnnouncement;

  /// No description provided for @newSubscription.
  ///
  /// In en, this message translates to:
  /// **'New Subscription'**
  String get newSubscription;

  /// No description provided for @newRoomNumber.
  ///
  /// In en, this message translates to:
  /// **'New Room Number:'**
  String get newRoomNumber;

  /// No description provided for @newToApp.
  ///
  /// In en, this message translates to:
  /// **'New to {appName}?'**
  String newToApp(Object appName);

  /// No description provided for @newUserRegister.
  ///
  /// In en, this message translates to:
  /// **'New user? Register'**
  String get newUserRegister;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @noAccountFound.
  ///
  /// In en, this message translates to:
  /// **'No account found. Try signing in using a different email address. Or, Sign Up using this one.'**
  String get noAccountFound;

  /// No description provided for @noAnnouncementsYet.
  ///
  /// In en, this message translates to:
  /// **'No announcements yet.'**
  String get noAnnouncementsYet;

  /// No description provided for @noCancel.
  ///
  /// In en, this message translates to:
  /// **'No, Cancel'**
  String get noCancel;

  /// No description provided for @noDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No devices found.'**
  String get noDevicesFound;

  /// No description provided for @noEventsFound.
  ///
  /// In en, this message translates to:
  /// **'No events found'**
  String get noEventsFound;

  /// No description provided for @noItems.
  ///
  /// In en, this message translates to:
  /// **'No {name}'**
  String noItems(Object name);

  /// No description provided for @noMatchingMembersFound.
  ///
  /// In en, this message translates to:
  /// **'No matching members found.'**
  String get noMatchingMembersFound;

  /// No description provided for @noOneIsHereYet.
  ///
  /// In en, this message translates to:
  /// **'No one is here yet.'**
  String get noOneIsHereYet;

  /// No description provided for @noOneIsHereYet1.
  ///
  /// In en, this message translates to:
  /// **'No one is here yet'**
  String get noOneIsHereYet1;

  /// No description provided for @noPendingJoinRequests.
  ///
  /// In en, this message translates to:
  /// **'No Pending Join Requests'**
  String get noPendingJoinRequests;

  /// No description provided for @noRoomsFound.
  ///
  /// In en, this message translates to:
  /// **'No rooms found.'**
  String get noRoomsFound;

  /// No description provided for @noRoomsNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'No rooms need help.'**
  String get noRoomsNeedHelp;

  /// No description provided for @noUpcomingEventsMessage.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t registered for any upcoming events.'**
  String get noUpcomingEventsMessage;

  /// No description provided for @notAuthorized.
  ///
  /// In en, this message translates to:
  /// **'Sorry, you aren\'t authorized to do that.'**
  String get notAuthorized;

  /// No description provided for @notifyMeAboutNewAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'Notify me about new announcements'**
  String get notifyMeAboutNewAnnouncements;

  /// No description provided for @notifyMeAboutNewEvents.
  ///
  /// In en, this message translates to:
  /// **'Notify me about new events'**
  String get notifyMeAboutNewEvents;

  /// No description provided for @ofTotal.
  ///
  /// In en, this message translates to:
  /// **'of {count}'**
  String ofTotal(int count);

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @owner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get owner;

  /// No description provided for @participantActions.
  ///
  /// In en, this message translates to:
  /// **'Participant Actions'**
  String get participantActions;

  /// Semantic label for participant actions, with userId as parameter.
  ///
  /// In en, this message translates to:
  /// **'Participant Actions for user with ID {userId}'**
  String participantActionsForUserWithId(Object userId);

  /// No description provided for @participantReassigned.
  ///
  /// In en, this message translates to:
  /// **'Participant Reassigned'**
  String get participantReassigned;

  /// No description provided for @participants.
  ///
  /// In en, this message translates to:
  /// **'Participants'**
  String get participants;

  /// No description provided for @participantsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong loading participants. Please refresh.'**
  String get participantsLoadError;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordRequirements.
  ///
  /// In en, this message translates to:
  /// **'Must be at least 6 characters long, and contain one lowercase and one uppercase letter.'**
  String get passwordRequirements;

  /// No description provided for @passwordInvalid.
  ///
  /// In en, this message translates to:
  /// **'Password is invalid. Click Forgot Password to reset it. Or, Sign Up again using a different email.'**
  String get passwordInvalid;

  /// No description provided for @passwordResetLinkSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset link sent to {email}'**
  String passwordResetLinkSent(Object email);

  /// No description provided for @pasteOrEnterAUrl.
  ///
  /// In en, this message translates to:
  /// **'Paste or enter a URL'**
  String get pasteOrEnterAUrl;

  /// No description provided for @pasteOrEnterUrl.
  ///
  /// In en, this message translates to:
  /// **'Paste or enter a URL'**
  String get pasteOrEnterUrl;

  /// No description provided for @people.
  ///
  /// In en, this message translates to:
  /// **'people'**
  String get people;

  /// No description provided for @person.
  ///
  /// In en, this message translates to:
  /// **'person'**
  String get person;

  /// No description provided for @pleaseEnterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address.'**
  String get pleaseEnterValidEmail;

  /// No description provided for @pleaseEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter a password'**
  String get pleaseEnterPassword;

  /// No description provided for @pleaseEnterValidPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid password'**
  String get pleaseEnterValidPassword;

  /// No description provided for @pleaseLogInOrSignUp.
  ///
  /// In en, this message translates to:
  /// **'Please log in or sign up'**
  String get pleaseLogInOrSignUp;

  /// No description provided for @postWasDeleted.
  ///
  /// In en, this message translates to:
  /// **'Post was deleted.'**
  String get postWasDeleted;

  /// No description provided for @posts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get posts;

  /// No description provided for @prerequisiteRequired.
  ///
  /// In en, this message translates to:
  /// **'Prerequisite Required'**
  String get prerequisiteRequired;

  /// No description provided for @pressToPromote.
  ///
  /// In en, this message translates to:
  /// **'Press to promote'**
  String get pressToPromote;

  /// No description provided for @primaryContent.
  ///
  /// In en, this message translates to:
  /// **'primary-content'**
  String get primaryContent;

  /// No description provided for @previewAgenda.
  ///
  /// In en, this message translates to:
  /// **'Preview Agenda'**
  String get previewAgenda;

  /// No description provided for @previewVideo.
  ///
  /// In en, this message translates to:
  /// **'Preview video'**
  String get previewVideo;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @profileButton.
  ///
  /// In en, this message translates to:
  /// **'Profile Button'**
  String get profileButton;

  /// No description provided for @proposeToRemoveUser.
  ///
  /// In en, this message translates to:
  /// **'Propose to remove user?'**
  String get proposeToRemoveUser;

  /// No description provided for @questionGoesHere.
  ///
  /// In en, this message translates to:
  /// **'Question goes here'**
  String get questionGoesHere;

  /// No description provided for @questionWithNumber.
  ///
  /// In en, this message translates to:
  /// **'Question {number}'**
  String questionWithNumber(Object number);

  /// No description provided for @raiseHandJoinSpeakerQueue.
  ///
  /// In en, this message translates to:
  /// **'Raise your hand to join the speaker queue'**
  String get raiseHandJoinSpeakerQueue;

  /// No description provided for @record.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get record;

  /// No description provided for @transcribe.
  ///
  /// In en, this message translates to:
  /// **'Transcribe'**
  String get transcribe;

  /// No description provided for @screenShare.
  ///
  /// In en, this message translates to:
  /// **'Screen Share'**
  String get screenShare;

  /// No description provided for @odometer.
  ///
  /// In en, this message translates to:
  /// **'Odometer'**
  String get odometer;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save Settings'**
  String get saveSettings;

  /// No description provided for @restoreSettings.
  ///
  /// In en, this message translates to:
  /// **'Restore Default Settings'**
  String get restoreSettings;

  /// No description provided for @devSettings.
  ///
  /// In en, this message translates to:
  /// **'Developer Settings'**
  String get devSettings;

  /// No description provided for @changedFromDefault.
  ///
  /// In en, this message translates to:
  /// **'Changed from default'**
  String get changedFromDefault;

  /// No description provided for @enterCategoryNum.
  ///
  /// In en, this message translates to:
  /// **'Enter Category {number}'**
  String enterCategoryNum(Object number);

  /// No description provided for @meetingEndMessage.
  ///
  /// In en, this message translates to:
  /// **'This meeting has ended. You may close this window.'**
  String get meetingEndMessage;

  /// No description provided for @meetingEndWithFollowMessage.
  ///
  /// In en, this message translates to:
  /// **'This meeting has ended. You may close this window or visit {name} to continue the conversation.'**
  String meetingEndWithFollowMessage(Object name);

  /// No description provided for @agendaPromptReady.
  ///
  /// In en, this message translates to:
  /// **'Your event is ready to start!'**
  String get agendaPromptReady;

  /// No description provided for @startEvent.
  ///
  /// In en, this message translates to:
  /// **'Start Event'**
  String get startEvent;

  /// No description provided for @agendaPromptWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for host to start the event...'**
  String get agendaPromptWaiting;

  /// No description provided for @raiseHandToJoin.
  ///
  /// In en, this message translates to:
  /// **'Raise your hand to join the speaker queue'**
  String get raiseHandToJoin;

  /// No description provided for @raiseHandToJoinSpeakerQueue.
  ///
  /// In en, this message translates to:
  /// **'Raise your hand to join the speaker queue'**
  String get raiseHandToJoinSpeakerQueue;

  /// No description provided for @raiseYourHandToJoinTheSpeakerQueue.
  ///
  /// In en, this message translates to:
  /// **'Raise your hand to join the speaker queue'**
  String get raiseYourHandToJoinTheSpeakerQueue;

  /// No description provided for @randomlyAssign.
  ///
  /// In en, this message translates to:
  /// **'Randomly Assign'**
  String get randomlyAssign;

  /// No description provided for @recentRooms.
  ///
  /// In en, this message translates to:
  /// **'Recent Rooms'**
  String get recentRooms;

  /// No description provided for @refreshConnection.
  ///
  /// In en, this message translates to:
  /// **'Refresh Connection'**
  String get refreshConnection;

  /// No description provided for @removeParticipant.
  ///
  /// In en, this message translates to:
  /// **'Remove Participant'**
  String get removeParticipant;

  /// No description provided for @removeSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Remove Suggestion'**
  String get removeSuggestion;

  /// No description provided for @removedFromEvent.
  ///
  /// In en, this message translates to:
  /// **'You were removed from this event and cannot rejoin.'**
  String get removedFromEvent;

  /// No description provided for @resources.
  ///
  /// In en, this message translates to:
  /// **'Resources'**
  String get resources;

  /// No description provided for @roomsCountMayChange.
  ///
  /// In en, this message translates to:
  /// **'Number of rooms may change if participants drop off.'**
  String get roomsCountMayChange;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveAgendaItem.
  ///
  /// In en, this message translates to:
  /// **'Save Agenda Item'**
  String get saveAgendaItem;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchEvents.
  ///
  /// In en, this message translates to:
  /// **'Search events'**
  String get searchEvents;

  /// No description provided for @searchTemplates.
  ///
  /// In en, this message translates to:
  /// **'Search templates'**
  String get searchTemplates;

  /// No description provided for @sectionNotFilledYet.
  ///
  /// In en, this message translates to:
  /// **'This section hasn\'t been filled in yet.'**
  String get sectionNotFilledYet;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @selectMaxParticipantCount.
  ///
  /// In en, this message translates to:
  /// **'Select max. participant count'**
  String get selectMaxParticipantCount;

  /// No description provided for @selectSpace.
  ///
  /// In en, this message translates to:
  /// **'Select space:'**
  String get selectSpace;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// No description provided for @setPayeeAccountDetails.
  ///
  /// In en, this message translates to:
  /// **'Set your payee account details'**
  String get setPayeeAccountDetails;

  /// No description provided for @setYourPayeeAccountDetails.
  ///
  /// In en, this message translates to:
  /// **'Set your payee account details'**
  String get setYourPayeeAccountDetails;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsFor.
  ///
  /// In en, this message translates to:
  /// **'Settings for {communityName}'**
  String settingsFor(Object communityName);

  /// No description provided for @showAnnouncementsButton.
  ///
  /// In en, this message translates to:
  /// **'Show Announcements Button'**
  String get showAnnouncementsButton;

  /// No description provided for @showOptions.
  ///
  /// In en, this message translates to:
  /// **'Show Options'**
  String get showOptions;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show Password'**
  String get showPassword;

  /// No description provided for @showSidebarButton.
  ///
  /// In en, this message translates to:
  /// **'Show Sidebar Button'**
  String get showSidebarButton;

  /// No description provided for @sidebarUnfollowButton.
  ///
  /// In en, this message translates to:
  /// **'Sidebar Unfollow Button'**
  String get sidebarUnfollowButton;

  /// No description provided for @sidebarFollowCommunityButton.
  ///
  /// In en, this message translates to:
  /// **'Sidebar Follow Space Button'**
  String get sidebarFollowCommunityButton;

  /// No description provided for @followCommunityButton.
  ///
  /// In en, this message translates to:
  /// **'Follow Space Button'**
  String get followCommunityButton;

  /// No description provided for @franklyLogo.
  ///
  /// In en, this message translates to:
  /// **'AllSides Logo'**
  String get franklyLogo;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @signingUp.
  ///
  /// In en, this message translates to:
  /// **'signing up'**
  String get signingUp;

  /// No description provided for @signInToApp.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {appName}'**
  String signInToApp(Object appName);

  /// No description provided for @signInWithEmail.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Email'**
  String get signInWithEmail;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @signUpOrSignInToContinue.
  ///
  /// In en, this message translates to:
  /// **'Sign up (or sign in using an existing account) to continue.'**
  String get signUpOrSignInToContinue;

  /// No description provided for @signUpToGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Sign up to get started.'**
  String get signUpToGetStarted;

  /// No description provided for @signUpWithEmail.
  ///
  /// In en, this message translates to:
  /// **'Sign up with Email'**
  String get signUpWithEmail;

  /// No description provided for @signUpWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign up with Google'**
  String get signUpWithGoogle;

  /// No description provided for @skipStripeAccountSetupForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip Stripe account setup for now'**
  String get skipStripeAccountSetupForNow;

  /// No description provided for @smartMatch.
  ///
  /// In en, this message translates to:
  /// **'Smart Match'**
  String get smartMatch;

  /// No description provided for @smartMatchParticipants.
  ///
  /// In en, this message translates to:
  /// **'Smart Match Participants'**
  String get smartMatchParticipants;

  /// No description provided for @socialFacebook.
  ///
  /// In en, this message translates to:
  /// **'Facebook URL'**
  String get socialFacebook;

  /// No description provided for @socialInstagram.
  ///
  /// In en, this message translates to:
  /// **'Instagram URL'**
  String get socialInstagram;

  /// No description provided for @socialLinkedIn.
  ///
  /// In en, this message translates to:
  /// **'LinkedIn URL'**
  String get socialLinkedIn;

  /// No description provided for @socialTwitter.
  ///
  /// In en, this message translates to:
  /// **'Twitter URL'**
  String get socialTwitter;

  /// No description provided for @somethingWentWrongTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get somethingWentWrongTryAgain;

  /// No description provided for @sorryVimeoVideoLookupFailed.
  ///
  /// In en, this message translates to:
  /// **'Sorry, vimeo video lookup failed.'**
  String get sorryVimeoVideoLookupFailed;

  /// No description provided for @sorryYoutubeVideoLookupFailed.
  ///
  /// In en, this message translates to:
  /// **'Sorry, youtube video lookup failed.'**
  String get sorryYoutubeVideoLookupFailed;

  /// No description provided for @spreadTheWord.
  ///
  /// In en, this message translates to:
  /// **'SPREAD THE WORD'**
  String get spreadTheWord;

  /// No description provided for @startCommunity.
  ///
  /// In en, this message translates to:
  /// **'Start a Space'**
  String get startCommunity;

  /// No description provided for @startTime.
  ///
  /// In en, this message translates to:
  /// **'Start Time'**
  String get startTime;

  /// No description provided for @submitChatButton.
  ///
  /// In en, this message translates to:
  /// **'Submit Chat Button'**
  String get submitChatButton;

  /// No description provided for @submitMessageButton.
  ///
  /// In en, this message translates to:
  /// **'Submit Message Button'**
  String get submitMessageButton;

  /// No description provided for @submitTagButton.
  ///
  /// In en, this message translates to:
  /// **'Submit Tag Button'**
  String get submitTagButton;

  /// No description provided for @suggest.
  ///
  /// In en, this message translates to:
  /// **'Suggest'**
  String get suggest;

  /// No description provided for @suggestAgendaItemHint.
  ///
  /// In en, this message translates to:
  /// **'You can suggest an agenda item and everyone can vote'**
  String get suggestAgendaItemHint;

  /// No description provided for @suggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get suggestions;

  /// No description provided for @tag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tag;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Tagline'**
  String get tagline;

  /// No description provided for @targetParticipantsPerRoom.
  ///
  /// In en, this message translates to:
  /// **'Target Participants\nPer Room'**
  String get targetParticipantsPerRoom;

  /// No description provided for @targetSize.
  ///
  /// In en, this message translates to:
  /// **'Target size'**
  String get targetSize;

  /// No description provided for @targetSizeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Target Size?'**
  String get targetSizeQuestion;

  /// No description provided for @templates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templates;

  /// No description provided for @termsAgreementPrefix.
  ///
  /// In en, this message translates to:
  /// **'By signing in, registering, or using {appName}, I agree to be bound by the '**
  String termsAgreementPrefix(Object appName);

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'{appName} Terms of Service'**
  String termsOfService(Object appName);

  /// No description provided for @textCopied.
  ///
  /// In en, this message translates to:
  /// **'Text copied!'**
  String get textCopied;

  /// No description provided for @thereWasAnErrorLoadingEventTemplates.
  ///
  /// In en, this message translates to:
  /// **'There was an error loading templates for this space.'**
  String get thereWasAnErrorLoadingEventTemplates;

  /// No description provided for @thisEventIsLocked.
  ///
  /// In en, this message translates to:
  /// **'This event is locked'**
  String get thisEventIsLocked;

  /// No description provided for @thisUrlWasNotFound.
  ///
  /// In en, this message translates to:
  /// **'This URL was not found.'**
  String get thisUrlWasNotFound;

  /// No description provided for @troubleshoot.
  ///
  /// In en, this message translates to:
  /// **'Troubleshoot'**
  String get troubleshoot;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Please try again'**
  String get tryAgain;

  /// No description provided for @turnOnAudioVideo.
  ///
  /// In en, this message translates to:
  /// **'Turn on Audio/Video?'**
  String get turnOnAudioVideo;

  /// No description provided for @twitterUrl.
  ///
  /// In en, this message translates to:
  /// **'Twitter URL'**
  String get twitterUrl;

  /// No description provided for @typeSomething.
  ///
  /// In en, this message translates to:
  /// **'Type something'**
  String get typeSomething;

  /// No description provided for @unfollow.
  ///
  /// In en, this message translates to:
  /// **'Unfollow'**
  String get unfollow;

  /// No description provided for @uniqueUrlDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Unique URL display name (Optional)'**
  String get uniqueUrlDisplayName;

  /// No description provided for @uniqueUrlDisplayNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Unique URL display name (Optional)'**
  String get uniqueUrlDisplayNameOptional;

  /// No description provided for @upcomingEvents.
  ///
  /// In en, this message translates to:
  /// **'Upcoming Events'**
  String get upcomingEvents;

  /// No description provided for @urlParameter.
  ///
  /// In en, this message translates to:
  /// **'URL Parameter'**
  String get urlParameter;

  /// No description provided for @usersAreInBreakoutRooms.
  ///
  /// In en, this message translates to:
  /// **'Users are in breakout rooms.'**
  String get usersAreInBreakoutRooms;

  /// No description provided for @videoElement.
  ///
  /// In en, this message translates to:
  /// **'{label}-video-element'**
  String videoElement(Object label);

  /// No description provided for @videoInputDevice.
  ///
  /// In en, this message translates to:
  /// **'Video Input Device:'**
  String get videoInputDevice;

  /// No description provided for @vimeoVideoLookupFailed.
  ///
  /// In en, this message translates to:
  /// **'Sorry, vimeo video lookup failed.'**
  String get vimeoVideoLookupFailed;

  /// No description provided for @waitingRoom.
  ///
  /// In en, this message translates to:
  /// **'Waiting Room'**
  String get waitingRoom;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to AllSides'**
  String get welcome;

  /// No description provided for @welcomeName.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}'**
  String welcomeName(Object name);

  /// No description provided for @welcomeToApp.
  ///
  /// In en, this message translates to:
  /// **'Welcome to {appName}'**
  String welcomeToApp(Object appName);

  /// No description provided for @whenNewItemsAdded.
  ///
  /// In en, this message translates to:
  /// **'When new {name} are added, you\'ll see them here.'**
  String whenNewItemsAdded(Object name);

  /// No description provided for @whenYouUpgrade.
  ///
  /// In en, this message translates to:
  /// **'when you upgrade'**
  String get whenYouUpgrade;

  /// No description provided for @wordCloud.
  ///
  /// In en, this message translates to:
  /// **'Word Cloud'**
  String get wordCloud;

  /// No description provided for @wordCloudPrompt.
  ///
  /// In en, this message translates to:
  /// **'Word Cloud Prompt'**
  String get wordCloudPrompt;

  /// No description provided for @wordCloudPromptRequired.
  ///
  /// In en, this message translates to:
  /// **'Word Cloud prompt is required'**
  String get wordCloudPromptRequired;

  /// No description provided for @errorLoadingWordCloudResponses.
  ///
  /// In en, this message translates to:
  /// **'Error loading word cloud responses'**
  String get errorLoadingWordCloudResponses;

  /// No description provided for @wordList.
  ///
  /// In en, this message translates to:
  /// **'Word List'**
  String get wordList;

  /// No description provided for @suggestionsWillShowUpHere.
  ///
  /// In en, this message translates to:
  /// **'Suggestions will show up here'**
  String get suggestionsWillShowUpHere;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @donate.
  ///
  /// In en, this message translates to:
  /// **'Donate'**
  String get donate;

  /// No description provided for @addAResource.
  ///
  /// In en, this message translates to:
  /// **'Add a resource'**
  String get addAResource;

  /// No description provided for @createPost.
  ///
  /// In en, this message translates to:
  /// **'Create post'**
  String get createPost;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @billing.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get billing;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// No description provided for @updateToPlan.
  ///
  /// In en, this message translates to:
  /// **'Update to {name}?'**
  String updateToPlan(Object name);

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwner;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleModerator.
  ///
  /// In en, this message translates to:
  /// **'Moderator'**
  String get roleModerator;

  /// No description provided for @roleFacilitator.
  ///
  /// In en, this message translates to:
  /// **'Facilitator'**
  String get roleFacilitator;

  /// No description provided for @roleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get roleMember;

  /// No description provided for @roleAttendee.
  ///
  /// In en, this message translates to:
  /// **'Attendee'**
  String get roleAttendee;

  /// No description provided for @upvoteDownvoteSuggestions.
  ///
  /// In en, this message translates to:
  /// **'You can upvote and downvote suggested agenda items to discuss'**
  String get upvoteDownvoteSuggestions;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @enterWordCloudPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Enter Word Cloud prompt'**
  String get enterWordCloudPromptHint;

  /// No description provided for @wordCloudLabelText.
  ///
  /// In en, this message translates to:
  /// **'Word Cloud Prompt'**
  String get wordCloudLabelText;

  /// No description provided for @wordCloudParticipantsInfo.
  ///
  /// In en, this message translates to:
  /// **'Participants will be asked to respond with a list of words or short phrases'**
  String get wordCloudParticipantsInfo;

  /// No description provided for @addRoom.
  ///
  /// In en, this message translates to:
  /// **'Add Room'**
  String get addRoom;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @bufferTimeDescription.
  ///
  /// In en, this message translates to:
  /// **'About {duration} of buffer time before event begins'**
  String bufferTimeDescription(Object duration);

  /// No description provided for @playsAt.
  ///
  /// In en, this message translates to:
  /// **'Plays at {time}'**
  String playsAt(Object time);

  /// No description provided for @introBeforeBreakouts.
  ///
  /// In en, this message translates to:
  /// **'About {duration} of intro before breakout rooms'**
  String introBeforeBreakouts(Object duration);

  /// No description provided for @bufferAndIntroTime.
  ///
  /// In en, this message translates to:
  /// **'About {buffer} of buffer time and {intro} of introduction before breakout rooms'**
  String bufferAndIntroTime(Object buffer, Object intro);

  /// No description provided for @addToCalendar.
  ///
  /// In en, this message translates to:
  /// **'Add to calendar'**
  String get addToCalendar;

  /// No description provided for @googleCalendar.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar'**
  String get googleCalendar;

  /// No description provided for @outlookCalendar.
  ///
  /// In en, this message translates to:
  /// **'Outlook Calendar'**
  String get outlookCalendar;

  /// No description provided for @office365Calendar.
  ///
  /// In en, this message translates to:
  /// **'Office 365 Calendar'**
  String get office365Calendar;

  /// No description provided for @iCalCalendar.
  ///
  /// In en, this message translates to:
  /// **'iCal Calendar'**
  String get iCalCalendar;

  /// No description provided for @refreshGuide.
  ///
  /// In en, this message translates to:
  /// **'Refresh Guide'**
  String get refreshGuide;

  /// No description provided for @createTemplateFromEvent.
  ///
  /// In en, this message translates to:
  /// **'Create Template from Event'**
  String get createTemplateFromEvent;

  /// No description provided for @duplicateEvent.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Event'**
  String get duplicateEvent;

  /// No description provided for @downloadMembersRegistrationData.
  ///
  /// In en, this message translates to:
  /// **'Download Members Registration Data'**
  String get downloadMembersRegistrationData;

  /// No description provided for @downloadChatsAndSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Download Chats and Suggestions'**
  String get downloadChatsAndSuggestions;

  /// No description provided for @participantCount.
  ///
  /// In en, this message translates to:
  /// **'{count} participants'**
  String participantCount(int count);

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @yesDelete.
  ///
  /// In en, this message translates to:
  /// **'Yes, Delete'**
  String get yesDelete;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @floatingChat.
  ///
  /// In en, this message translates to:
  /// **'Floating Chat'**
  String get floatingChat;

  /// No description provided for @youCanChangeThisLater.
  ///
  /// In en, this message translates to:
  /// **'You can change this later'**
  String get youCanChangeThisLater;

  /// No description provided for @youNeedToBeLoggedInToDoThis.
  ///
  /// In en, this message translates to:
  /// **'You need to be logged in to do this.'**
  String get youNeedToBeLoggedInToDoThis;

  /// No description provided for @youWereRemovedFromThisEventAndCannotRejoin.
  ///
  /// In en, this message translates to:
  /// **'You were removed from this event and cannot rejoin.'**
  String get youWereRemovedFromThisEventAndCannotRejoin;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your Name'**
  String get yourName;

  /// No description provided for @youtubeVideoLookupFailed.
  ///
  /// In en, this message translates to:
  /// **'Sorry, youtube video lookup failed.'**
  String get youtubeVideoLookupFailed;

  /// No description provided for @zoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get zoom;

  /// No description provided for @helpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get helpCenter;

  /// No description provided for @prereqRequired.
  ///
  /// In en, this message translates to:
  /// **'Prerequisite required'**
  String get prereqRequired;

  /// No description provided for @myCommunities.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get myCommunities;

  /// No description provided for @youHaventJoinedAnyCommunities.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t joined any spaces.'**
  String get youHaventJoinedAnyCommunities;

  /// No description provided for @logo.
  ///
  /// In en, this message translates to:
  /// **'Logo'**
  String get logo;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @makeThisSpacePrivate.
  ///
  /// In en, this message translates to:
  /// **'Make this space private'**
  String get makeThisSpacePrivate;

  /// No description provided for @emailConsentText.
  ///
  /// In en, this message translates to:
  /// **'I agree to receive emails from AllSides and to the '**
  String get emailConsentText;

  /// No description provided for @allsidesPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'AllSides Privacy Policy'**
  String get allsidesPrivacyPolicy;

  /// No description provided for @toCreateYourSpaceSignIn.
  ///
  /// In en, this message translates to:
  /// **'To create your space, first sign in.'**
  String get toCreateYourSpaceSignIn;

  /// No description provided for @newCommunity.
  ///
  /// In en, this message translates to:
  /// **'New space'**
  String get newCommunity;

  /// No description provided for @editTheCommunity.
  ///
  /// In en, this message translates to:
  /// **'edit the space.'**
  String get editTheCommunity;

  /// No description provided for @editTheCommunityTemplate.
  ///
  /// In en, this message translates to:
  /// **'edit the template.'**
  String get editTheCommunityTemplate;

  /// No description provided for @communityName.
  ///
  /// In en, this message translates to:
  /// **'Space name'**
  String get communityName;

  /// No description provided for @communityDescription.
  ///
  /// In en, this message translates to:
  /// **'Space description'**
  String get communityDescription;

  /// No description provided for @updateCommunity.
  ///
  /// In en, this message translates to:
  /// **'Update space'**
  String get updateCommunity;

  /// No description provided for @newEventForWhichCommunity.
  ///
  /// In en, this message translates to:
  /// **'New event for which template?'**
  String get newEventForWhichCommunity;

  /// No description provided for @createANewCommunity.
  ///
  /// In en, this message translates to:
  /// **'Create a new template'**
  String get createANewCommunity;

  /// No description provided for @noCommunityAssociation.
  ///
  /// In en, this message translates to:
  /// **'No template association'**
  String get noCommunityAssociation;
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
      <String>['en', 'es', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script+country codes are specified.
  switch (locale.toString()) {
    case 'zh_Hant_TW':
      return AppLocalizationsZhHantTw();
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
