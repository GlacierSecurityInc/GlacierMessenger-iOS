//
//  OTRXLFormCreator.m
//  ChatSecure
//
//  Created by David Chiles on 5/12/15.
//  Copyright (c) 2015 Chris Ballinger. All rights reserved.
//

#import "OTRXLFormCreator.h"
@import XLForm;
#import "OTRXMPPAccount.h"
#import "OTRImages.h"
#import "Glacier-Swift.h"

NSString *const kOTRXLFormCustomizeUsernameSwitchTag        = @"kOTRXLFormCustomizeUsernameSwitchTag";
NSString *const kOTRXLFormNicknameTextFieldTag        = @"kOTRXLFormNicknameTextFieldTag";
NSString *const kOTRXLFormUsernameTextFieldTag        = @"kOTRXLFormUsernameTextFieldTag";
NSString *const kOTRXLFormPasswordTextFieldTag        = @"kOTRXLFormPasswordTextFieldTag";
NSString *const kOTRXLFormRememberPasswordSwitchTag   = @"kOTRXLFormRememberPasswordSwitchTag";
NSString *const kOTRXLFormLoginAutomaticallySwitchTag = @"kOTRXLFormLoginAutomaticallySwitchTag";
NSString *const kOTRXLFormHostnameTextFieldTag        = @"kOTRXLFormHostnameTextFieldTag";
NSString *const kOTRXLFormPortTextFieldTag            = @"kOTRXLFormPortTextFieldTag";
NSString *const kOTRXLFormResourceTextFieldTag        = @"kOTRXLFormResourceTextFieldTag";
NSString *const kOTRXLFormBypassNetworkSwitchTag      = @"kOTRXLFormBypassNetworkSwitchTag";

NSString *const kOTRXLFormShowAdvancedTag               = @"kOTRXLFormShowAdvancedTag";

NSString *const kOTRXLFormGenerateSecurePasswordTag               = @"kOTRXLFormGenerateSecurePasswordTag";

NSString *const kOTRXLFormAutomaticURLFetchTag               = @"kOTRXLFormAutomaticURLFetchTag";


@implementation XLFormDescriptor (OTRAccount)

+ (instancetype) existingAccountFormWithAccount:(OTRAccount *)account
{
    XLFormDescriptor *descriptor = [self formForAccountType:account.accountType createAccount:NO];
    
    [[descriptor formRowWithTag:kOTRXLFormUsernameTextFieldTag] setValue:account.username];
    [[descriptor formRowWithTag:kOTRXLFormPasswordTextFieldTag] setValue:account.password];
    [[descriptor formRowWithTag:kOTRXLFormRememberPasswordSwitchTag] setValue:@(account.rememberPassword)];
    [[descriptor formRowWithTag:kOTRXLFormLoginAutomaticallySwitchTag] setValue:@(account.autologin)];
    [[descriptor formRowWithTag:kOTRXLFormBypassNetworkSwitchTag] setValue:@(account.bypassNetworkCheck)];
    
    if([account isKindOfClass:[OTRXMPPAccount class]]) {
        OTRXMPPAccount *xmppAccount = (OTRXMPPAccount *)account;
        [[descriptor formRowWithTag:kOTRXLFormNicknameTextFieldTag] setValue:xmppAccount.displayName];
        [[descriptor formRowWithTag:kOTRXLFormHostnameTextFieldTag] setValue:xmppAccount.domain];
        [[descriptor formRowWithTag:kOTRXLFormPortTextFieldTag] setValue:@(xmppAccount.port)];
        [[descriptor formRowWithTag:kOTRXLFormResourceTextFieldTag] setValue:xmppAccount.resource];
        [[descriptor formRowWithTag:kOTRXLFormAutomaticURLFetchTag] setValue:@(!xmppAccount.disableAutomaticURLFetching)];
    }
    
    return descriptor;
}

+ (instancetype) registerNewAccountFormWithAccountType:(OTRAccountType)accountType {
    return [self formForAccountType:accountType createAccount:YES];
}

+ (instancetype) existingAccountFormWithAccountType:(OTRAccountType)accountType {
    return [self formForAccountType:accountType createAccount:NO];
}

+ (XLFormDescriptor *)formForAccountType:(OTRAccountType)accountType createAccount:(BOOL)createAccount
{
    XLFormDescriptor *descriptor = nil;
    XLFormRowDescriptor *nicknameRow = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormNicknameTextFieldTag rowType:XLFormRowDescriptorTypeText title:@"Display Name"];
    
    if (createAccount) {
        descriptor = [XLFormDescriptor formDescriptorWithTitle:SIGN_UP_STRING()];
        descriptor.assignFirstResponderOnShow = YES;
        
        XLFormSectionDescriptor *basicSection = [XLFormSectionDescriptor formSectionWithTitle:Basic_Setup()];
        basicSection.footerTitle = Basic_Setup_Hint();
        nicknameRow.required = YES;
        [basicSection addFormRow:nicknameRow];
        
        XLFormSectionDescriptor *showAdvancedSection = [XLFormSectionDescriptor formSectionWithTitle:nil];
        XLFormRowDescriptor *showAdvancedRow = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormShowAdvancedTag rowType:XLFormRowDescriptorTypeBooleanSwitch title:Show_Advanced_Options()];
        showAdvancedRow.value = @0;
        [showAdvancedSection addFormRow:showAdvancedRow];
        
        XLFormSectionDescriptor *accountSection = [XLFormSectionDescriptor formSectionWithTitle:ACCOUNT_STRING()];
        accountSection.footerTitle = Generate_Secure_Password_Hint();
        accountSection.hidden = [NSString stringWithFormat:@"$%@==0", kOTRXLFormShowAdvancedTag];
        XLFormRowDescriptor *generatePasswordRow = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormGenerateSecurePasswordTag rowType:XLFormRowDescriptorTypeBooleanSwitch title:Generate_Secure_Password()];
        generatePasswordRow.value = @1;
        XLFormRowDescriptor *customizeUsernameRow = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormCustomizeUsernameSwitchTag rowType:XLFormRowDescriptorTypeBooleanSwitch title:Customize_Username()];
        customizeUsernameRow.value = @0;
        XLFormRowDescriptor *passwordRow = [self passwordTextFieldRowDescriptorWithValue:nil];
        passwordRow.hidden = [NSString stringWithFormat:@"$%@==1", kOTRXLFormGenerateSecurePasswordTag];
        XLFormRowDescriptor *usernameRow = [self usernameTextFieldRowDescriptorWithValue:nil];
        usernameRow.hidden = [NSString stringWithFormat:@"$%@==0", kOTRXLFormCustomizeUsernameSwitchTag];
        [accountSection addFormRow:customizeUsernameRow];
        [accountSection addFormRow:usernameRow];
        [accountSection addFormRow:generatePasswordRow];
        [accountSection addFormRow:passwordRow];
        
        XLFormSectionDescriptor *otherSection = [XLFormSectionDescriptor formSectionWithTitle:OTHER_STRING()];
        otherSection.footerTitle = AUTO_URL_FETCH_WARNING_STRING();
        otherSection.hidden = [NSString stringWithFormat:@"$%@==0", kOTRXLFormShowAdvancedTag];
        [otherSection addFormRow:[self autoFetchRowDescriptorWithValue:YES]];
        
        [descriptor addFormSection:basicSection];
        [descriptor addFormSection:showAdvancedSection];
        [descriptor addFormSection:accountSection];
        [descriptor addFormSection:otherSection];
    } else {
        descriptor = [XLFormDescriptor formDescriptorWithTitle:LOGIN_STRING()];
        
        XLFormSectionDescriptor *basicSection = [XLFormSectionDescriptor formSectionWithTitle:@"ACCOUNT INFO"];
        XLFormSectionDescriptor *advancedSection = [XLFormSectionDescriptor formSectionWithTitle:@"VPN VERIFICATION"]; 
        
        [nicknameRow.cellConfigAtConfigure setObject:OPTIONAL_STRING() forKey:@"textField.placeholder"];
        [basicSection addFormRow:nicknameRow];
        
        switch (accountType) {
            case OTRAccountTypeJabber:{
                [basicSection addFormRow:[self jidTextFieldRowDescriptorWithValue:nil]];
                [basicSection addFormRow:[self passwordTextFieldRowDescriptorWithValue:nil]];
                [basicSection addFormRow:[self rememberPasswordRowDescriptorWithValue:YES]];
                [basicSection addFormRow:[self loginAutomaticallyRowDescriptorWithValue:YES]];
                
                [advancedSection addFormRow:[self hostnameRowDescriptorWithValue:[OTRXMPPAccount defaultHost]]];
                [advancedSection addFormRow:[self portRowDescriptorWithValue:@([OTRXMPPAccount defaultPort])]];
                [advancedSection addFormRow:[self resourceRowDescriptorWithValue:[OTRXMPPAccount newResource]]];
                [advancedSection addFormRow:[self autoFetchRowDescriptorWithValue:YES]];
                [advancedSection addFormRow:[self bypassNetworkCheckRowDescriptorWithValue:YES]];
                
                break;
            }
            case OTRAccountTypeGoogleTalk: {
                XLFormRowDescriptor *usernameRow = [self jidTextFieldRowDescriptorWithValue:nil];
                usernameRow.disabled = @(YES);
                
                [basicSection addFormRow:usernameRow];
                [basicSection addFormRow:[self loginAutomaticallyRowDescriptorWithValue:YES]];
                
                [advancedSection addFormRow:[self resourceRowDescriptorWithValue:nil]];
                [advancedSection addFormRow:[self autoFetchRowDescriptorWithValue:YES]];
                
                break;
            }
                
            default:
                break;
        }
        
        [descriptor addFormSection:basicSection];
        [descriptor addFormSection:advancedSection];
    }
    return descriptor;
}

+ (XLFormRowDescriptor *)textfieldFormDescriptorType:(NSString *)type withTag:(NSString *)tag title:(NSString *)title placeHolder:(NSString *)placeholder value:(id)value
{
    XLFormRowDescriptor *textFieldDescriptor = [XLFormRowDescriptor formRowDescriptorWithTag:tag rowType:type title:title];
    textFieldDescriptor.value = value;
    if (placeholder) {
        [textFieldDescriptor.cellConfigAtConfigure setObject:placeholder forKey:@"textField.placeholder"];
    }
    
    return textFieldDescriptor;
}

+ (XLFormRowDescriptor *)jidTextFieldRowDescriptorWithValue:(NSString *)value
{
    XLFormRowDescriptor *usernameDescriptor = [self textfieldFormDescriptorType:XLFormRowDescriptorTypeEmail withTag:kOTRXLFormUsernameTextFieldTag title:USERNAME_STRING() placeHolder:@"" value:value];
    usernameDescriptor.value = value;
    usernameDescriptor.required = YES;
    [usernameDescriptor addValidator:[[OTRUsernameValidator alloc] init]];
    return usernameDescriptor;
}

+ (XLFormRowDescriptor *)usernameTextFieldRowDescriptorWithValue:(NSString *)value
{
    XLFormRowDescriptor *usernameDescriptor = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormUsernameTextFieldTag rowType:[OTRUsernameCell defaultRowDescriptorType] title:USERNAME_STRING()];
    usernameDescriptor.value = value;
    usernameDescriptor.required = YES;
    [usernameDescriptor addValidator:[[OTRUsernameValidator alloc] init]];
    return usernameDescriptor;
}

+ (XLFormRowDescriptor *)passwordTextFieldRowDescriptorWithValue:(NSString *)value
{
    XLFormRowDescriptor *passwordDescriptor = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormPasswordTextFieldTag rowType:XLFormRowDescriptorTypePassword title:PASSWORD_STRING()];
    passwordDescriptor.value = value;
    passwordDescriptor.required = YES;
    [passwordDescriptor.cellConfigAtConfigure setObject:REQUIRED_STRING() forKey:@"textField.placeholder"];
    
    return passwordDescriptor;
}

+ (XLFormRowDescriptor *)rememberPasswordRowDescriptorWithValue:(BOOL)value
{
    XLFormRowDescriptor *switchDescriptor = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormRememberPasswordSwitchTag rowType:XLFormRowDescriptorTypeBooleanSwitch title:REMEMBER_PASSWORD_STRING()];
    switchDescriptor.value = @(value);
    switchDescriptor.hidden = @YES;
    
    return switchDescriptor;
}

+ (XLFormRowDescriptor *)bypassNetworkCheckRowDescriptorWithValue:(BOOL)value
{
    XLFormRowDescriptor *switchDescriptor = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormBypassNetworkSwitchTag rowType:XLFormRowDescriptorTypeBooleanSwitch title:@"Bypass Network Check"];
    switchDescriptor.value = @(value);
    
    return switchDescriptor;
}

+ (XLFormRowDescriptor *)loginAutomaticallyRowDescriptorWithValue:(BOOL)value
{
    XLFormRowDescriptor *loginDescriptor = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormLoginAutomaticallySwitchTag rowType:XLFormRowDescriptorTypeBooleanSwitch title:LOGIN_AUTOMATICALLY_STRING()];
    loginDescriptor.value = @(value);
    loginDescriptor.hidden = @YES;
    
    return loginDescriptor;
}

+ (XLFormRowDescriptor *)hostnameRowDescriptorWithValue:(NSString *)value
{
    NSString *defaultHostString = [OTRXMPPAccount defaultHost];
    XLFormRowDescriptor *hostrowDescriptor = [self textfieldFormDescriptorType:XLFormRowDescriptorTypeURL withTag:kOTRXLFormHostnameTextFieldTag title:HOSTNAME_STRING() placeHolder:defaultHostString value:value];
    hostrowDescriptor.hidden = @YES;
    return hostrowDescriptor;
}

+ (XLFormRowDescriptor *)portRowDescriptorWithValue:(NSNumber *)value
{
    NSString *defaultPortNumberString = [NSString stringWithFormat:@"%d",[OTRXMPPAccount defaultPort]];
    
    XLFormRowDescriptor *portRowDescriptor = [self textfieldFormDescriptorType:XLFormRowDescriptorTypeInteger withTag:kOTRXLFormPortTextFieldTag title:PORT_STRING() placeHolder:defaultPortNumberString value:value];
    
    //Regex between 0 and 65536 for valid ports or empty
    [portRowDescriptor addValidator:[XLFormRegexValidator formRegexValidatorWithMsg:@"Incorect port number" regex:@"^$|^([1-9][0-9]{0,3}|[1-5][0-9]{0,4}|6[0-5]{0,2}[0-3][0-5])$"]];
    portRowDescriptor.hidden = @YES;
    
    return portRowDescriptor;
}

+ (XLFormRowDescriptor*) autoFetchRowDescriptorWithValue:(BOOL)value {
    XLFormRowDescriptor *autoFetchRow = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormAutomaticURLFetchTag rowType:XLFormRowDescriptorTypeBooleanSwitch title:AUTO_URL_FETCH_STRING()];
    autoFetchRow.value = @(value);
    autoFetchRow.hidden = @YES;
    return autoFetchRow;
}

+ (XLFormRowDescriptor *)resourceRowDescriptorWithValue:(NSString *)value
{
    XLFormRowDescriptor *resourceRowDescriptor = [XLFormRowDescriptor formRowDescriptorWithTag:kOTRXLFormResourceTextFieldTag rowType:XLFormRowDescriptorTypeText title:RESOURCE_STRING()];
    resourceRowDescriptor.value = value;
    resourceRowDescriptor.hidden = @YES; 
    
    return resourceRowDescriptor;
}

@end
