//
//  OTRConstants.h
//  Off the Record
//
//  Created by David Chiles on 6/28/12.
//  Copyright (c) 2012 Chris Ballinger. All rights reserved.
//
//  This file is part of ChatSecure.
//
//  ChatSecure is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ChatSecure is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ChatSecure.  If not, see <http://www.gnu.org/licenses/>.
#import "OTRConstants.h"

NSString *const kOTRProtocolLoginSuccess                   = @"LoginSuccessNotification";

NSString *const kOTRProtocolTypeXMPP = @"xmpp";
NSString *const kOTRProtocolTypeAIM  = @"prpl-oscar";

NSString *const kOTRNotificationAccountNameKey       = @"kOTRNotificationAccountNameKey";
NSString *const kOTRNotificationUserNameKey          = @"kOTRNotificationUserNameKey";
NSString *const kOTRNotificationProtocolKey          = @"kOTRNotificationProtocolKey";
NSString *const kOTRNotificationBuddyUniqueIdKey     = @"kOTRNotificationBuddyUniqueIdKey";
NSString *const kOTRNotificationAccountUniqueIdKey   = @"kOTRNotificationAccountUniqueIdKey";
NSString *const kOTRNotificationAccountCollectionKey = @"kOTRNotificationAccountCollectionKey";


NSString *const kOTRServiceName            = @"org.chatsecure.ChatSecure";
NSString *const kOTRCertificateServiceName = @"org.chatsecure.ChatSecure.Certificate";

NSString *const kGlacierGroup      = @"group.com.glaciersec.apps";
NSString *const kGlacierAcct       = @"com.glaciersec.Acct";
NSString *const kGlacierKeyGroup      = @"5MXM7J8H38group.com.glaciersec.access";
NSString *const kCognitoAcct       = @"com.glaciersec.Cognito";
NSString *const kGlacierVpn       = @"com.glaciersec.Vpn";

NSString *const kOTRSettingKeyFontSize                 = @"kOTRSettingKeyFontSize";
NSString *const kOTRSettingKeyDeleteOnDisconnect       = @"kOTRSettingKeyDeleteOnDisconnect";
NSString *const kOTRSettingKeyAllowDBPassphraseBackup  = @"kOTRSettingKeyAllowDBPassphraseBackup";
NSString *const kOTRSettingKeyShowDisconnectionWarning = @"kOTRSettingKeyShowDisconnectionWarning";
NSString *const kOTRSettingUserAgreedToEULA            = @"kOTRSettingUserAgreedToEULA";
NSString *const kOTRSettingAccountsKey                 = @"kOTRSettingAccountsKey";
NSString *const kOTRSettingsValueUpdatedNotification = @"kOTRSettingsValueUpdatedNotification";
NSString *const kGlacierCoreConnection = @"kGlacierCoreConnection";

NSString *const kOTRPushEnabledKey = @"kOTRPushEnabledKey";

NSString *const kOTRAppVersionKey     = @"kOTRAppVersionKey";

NSString *const OTRArchiverKey = @"OTRArchiverKey";

NSString *const kOTRErrorDomain = @"com.glaciersecurity";


NSString *const OTRUserNotificationsUNTextInputReply = @"OTRUserNotificationsUNTextInputReply";
NSString *const OTRUserNotificationsChanged = @"OTRUserNotificationsChanged";
NSString *const OTRPushAccountDeviceChanged = @"OTRPushAccountDeviceChanged";
NSString *const OTRPushAccountTokensChanged = @"OTRPushAccountTokensChanged";


NSString *const OTRSuccessfulRemoteNotificationRegistration = @"OTRSuccessfulRemoteNotificationRegistration";

NSString *const OTRYapDatabasePassphraseAccountName = @"OTRYapDatabasePassphraseAccountName";

NSString *const OTRYapDatabaseName = @"ChatSecureYap.sqlite";

//Noticications
NSString *const kOTRNotificationAccountKey = @"kOTRNotificationAccountKey";
NSString *const kOTRNotificationThreadKey = @"kOTRNotificationThreadKey";
NSString *const kOTRNotificationThreadCollection = @"kOTRNotificationThreadCollection";
NSString *const kOTRNotificationType = @"kOTRNotificationType";
NSString *const kOTRNotificationTypeNone = @"kOTRNotificationTypeNone";
NSString *const kOTRNotificationTypeSubscriptionRequest = @"kOTRNotificationTypeSubscriptionRequest";
NSString *const kOTRNotificationTypeApprovedBuddy = @"kOTRNotificationTypeApprovedBuddy";
NSString *const kOTRNotificationTypeConnectionError = @"kOTRNotificationTypeConnectionError";
NSString *const kOTRNotificationTypeChatMessage = @"kOTRNotificationTypeChatMessage";

// Twilio Calls
NSString *const kNotificationTypeCallRequest = @"kNotificationTypeCallRequest";
NSString *const kNotificationTypeCallAccept = @"kNotificationTypeCallAccept";
NSString *const kNotificationTypeCallReject = @"kNotificationTypeCallReject";
NSString *const kNotificationTypeCallBusy = @"kNotificationTypeCallBusy";
NSString *const kNotificationTypeCallCancel = @"kNotificationTypeCallCancel";
NSString *const kNotificationCallIdKey   = @"call_id";
NSString *const kNotificationCallerKey   = @"caller";
//NSString *const kNotificationCallTypeKey   = @"type";
NSString *const kNotificationCallStatusKey   = @"status";
NSString *const kNotificationCallRoomnameKey   = @"roomname";


//NSUserDefaults
NSString *const kOTRShowOMEMOGroupEncryptionKey = @"kOTRShowOMEMOGroupEncryptionKey";
NSString *const kOTREnableDebugLoggingKey = @"kOTREnableDebugLoggingKey";

extern NSString *const kOTREnableDebugLoggingKey;
//Chatview
CGFloat const kOTRSentDateFontSize            = 13;
CGFloat const kOTRDeliveredFontSize           = 13;
CGFloat const kOTRMessageFontSize             = 16;
CGFloat const kOTRMessageSentDateLabelHeight  = kOTRSentDateFontSize + 7;
CGFloat const kOTRMessageDeliveredLabelHeight = kOTRDeliveredFontSize + 7;

NSUInteger const kOTRMinimumPassphraseLength = 8;
NSUInteger const kOTRMaximumPassphraseLength = 64;
