//
//  NewCognitoPasswordRequiredViewController
//  Created by David Tucker (davidtucker.net) on 5/4/17.
//
//  Copyright (c) 2017 David Tucker
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import UIKit
import OTRAssets
import AWSCognitoIdentityProvider

import SAMKeychain;

open class NewCognitoPasswordRequiredViewController: UIViewController {
    
    @IBOutlet weak var newPasswordLabel: UILabel!
    @IBOutlet weak var passwordRulesLabel: UILabel!
    @IBOutlet weak var newPasswordButton: UIButton!
    @IBOutlet weak var newPasswordInput: UITextField!
    @IBOutlet weak var confirmNewPasswordInput: UITextField!
    @IBOutlet weak var invalidPasswordLabel: UILabel!
    @IBOutlet weak var invalidConfirmPasswordLabel: UILabel!
    @IBOutlet weak var invalidMatchLabel: UILabel!
    @IBOutlet weak var confirmPasswordLabel: UILabel!
    
    let eyeLabel = InsetsLabel(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
    var currentUserAttributes:[String:String]?
    var resetPasswordCompletion: AWSTaskCompletionSource<AWSCognitoIdentityNewPasswordRequiredDetails>?
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.tapScreen(_:)))
        self.view.addGestureRecognizer(tapGesture)
        self.invalidPasswordLabel.isHidden = true
        self.invalidConfirmPasswordLabel.isHidden = true
        self.invalidMatchLabel.isHidden = true
        
        self.newPasswordInput.rightViewMode = UITextFieldViewMode.always
        if #available(iOS 13.0, *) {
            eyeLabel.contentInsets = UIEdgeInsetsMake(0, 0, 0, 10)
        }
        eyeLabel.contentMode = UIViewContentMode.center
        eyeLabel.font = UIFont(name: kFontAwesomeFont, size: 20)
        eyeLabel.textAlignment = NSTextAlignment.center
        eyeLabel.textColor = UIColor.darkText
        eyeLabel.text = ""
        self.newPasswordInput.rightView = eyeLabel
        eyeLabel.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.eyeTap))
        eyeLabel.addGestureRecognizer(tap)
        if #available(iOS 13.0, *) {
            self.isModalInPresentation = true
        }
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.newPasswordInput.text = nil
        self.confirmNewPasswordInput.text = nil
        self.confirmPasswordLabel.text = "CONFIRM PASSWORD"
        self.newPasswordLabel.text = "NEW PASSWORD"
        self.passwordRulesLabel.text = "Password must be at least 8 characters and include at least one upper case letter, lower case letter, and number."
        self.newPasswordButton.setTitle("CHANGE PASSWORD", for: UIControlState.normal)
        self.invalidPasswordLabel.text = "Invalid Password"
        self.invalidConfirmPasswordLabel.text = "Invalid Password"
        self.invalidMatchLabel.text = "Passwords must match"
    }
    
    @objc func eyeTap(sender:UITapGestureRecognizer) {
        let isFirstResponder = eyeLabel.isFirstResponder;
        if (isFirstResponder) { self.eyeLabel.resignFirstResponder() }
        if (self.newPasswordInput.isSecureTextEntry) {
            self.eyeLabel.text = ""
        } else {
            self.eyeLabel.text = ""
        }
        self.newPasswordInput.isSecureTextEntry.toggle()
        self.confirmNewPasswordInput.isSecureTextEntry.toggle()
        if (isFirstResponder) { self.eyeLabel.becomeFirstResponder() }
    }
    
    @IBAction func changePasswordPressed(_ sender: Any) {
        self.dismissKeyboard()
        
        if (self.validateFields()) {
            let trimpass = newPasswordInput.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let idresult = SAMKeychain.password(forService: kGlacierGroup, account: kCognitoAcct, accessGroup: kGlacierGroup, error: nil) {
                let result = SAMKeychain.setPassword(trimpass!, forService:kGlacierGroup, account:idresult, accessGroup:kGlacierGroup, error: nil)
                if (!result) {
                    DDLogError("Error saving password to keychain")
                }
            }
            
            let userAttributes:[String:String] = [:]
            let details = AWSCognitoIdentityNewPasswordRequiredDetails(proposedPassword: trimpass!, userAttributes: userAttributes)
            self.resetPasswordCompletion?.set(result: details)
        }
    }
    
    @objc func tapScreen(_ sender: UITapGestureRecognizer) {
        self.dismissKeyboard()
    }
    
    func dismissKeyboard() {
        self.newPasswordInput.resignFirstResponder()
        self.confirmNewPasswordInput.resignFirstResponder()
    }
    
    func validateFields() -> Bool {
        self.invalidPasswordLabel.isHidden = true
        self.invalidConfirmPasswordLabel.isHidden = true
        self.invalidMatchLabel.isHidden = true
        
        var valid = true
        let trimpass = newPasswordInput.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmtrimpass = confirmNewPasswordInput.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if ((trimpass?.isEmpty)! || !(isPasswordValid(trimpass!))) {
            valid = false
            self.invalidPasswordLabel.isHidden = false
        }
        
        if (valid && ((confirmtrimpass?.isEmpty)! || !(isPasswordValid(confirmtrimpass!)))) {
            valid = false
            self.invalidConfirmPasswordLabel.isHidden = false
        }
        
        if (valid && trimpass != confirmtrimpass) {
            valid = false
            self.invalidMatchLabel.isHidden = false
        }
        
        return valid
    }
    
    func isPasswordValid(_ password: String) -> Bool
    {
        let regularExpression = "^(?=.*?[a-z])(?=.*?[A-Z])(?=.*?[0-9])[A-Za-z0-9$@#!%*?&-_]{8,}$"
        let passwordValidation = NSPredicate.init(format: "SELF MATCHES %@", regularExpression)
        return passwordValidation.evaluate(with: password)
    }
}

extension NewCognitoPasswordRequiredViewController: AWSCognitoIdentityNewPasswordRequired {
    
    public func getNewPasswordDetails(_ newPasswordRequiredInput: AWSCognitoIdentityNewPasswordRequiredInput, newPasswordRequiredCompletionSource: AWSTaskCompletionSource<AWSCognitoIdentityNewPasswordRequiredDetails>) {
        self.currentUserAttributes = newPasswordRequiredInput.userAttributes
        self.resetPasswordCompletion = newPasswordRequiredCompletionSource
    }
    
    public func didCompleteNewPasswordStepWithError(_ error: Error?) {
        DispatchQueue.main.async {
            if let error = error as NSError? {
                // if session expired restart login
                let errmsg = error.userInfo["message"] as? String
                if let errstring = errmsg, errstring.hasPrefix("Invalid session") {
                    AWSAccountManager.shared.setExpiredSession()
                    self.newPasswordInput.text = nil
                    self.dismiss(animated: true, completion: nil)
                } else {
                    let alertController = UIAlertController(title: error.userInfo["__type"] as? String,
                        message: errmsg, preferredStyle: .alert)
                    let retryAction = UIAlertAction(title: "Retry", style: .default, handler:nil)
                    alertController.addAction(retryAction)
                    self.present(alertController, animated: true, completion:  nil)
                }
            } else {
                self.newPasswordInput.text = nil
                self.dismiss(animated: true, completion: nil)
            }
        }
    }
}
