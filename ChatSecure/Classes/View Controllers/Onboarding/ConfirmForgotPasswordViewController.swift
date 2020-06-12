//
//  ConfirmForgotPasswordViewController.swift
//  Created on 12/16/19.
//  Copyright © 2019 Glacier Security. All rights reserved.
//

import Foundation
import AWSCognitoIdentityProvider

class ConfirmForgotPasswordViewController: UIViewController {
    
    var user: AWSCognitoIdentityUser?
    
    @IBOutlet weak var confirmationCode: UITextField!
    @IBOutlet weak var proposedPassword: UITextField!
    
    @IBOutlet weak var invalidConfirmationLabel: UILabel!
    @IBOutlet weak var invalidPasswordLabel: UILabel!
    
    let eyeLabel = InsetsLabel(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.tapScreen(_:)))
        self.view.addGestureRecognizer(tapGesture)
        self.invalidConfirmationLabel.isHidden = true
        self.invalidPasswordLabel.isHidden = true
        
        self.proposedPassword.rightViewMode = UITextFieldViewMode.always
        if #available(iOS 13.0, *) {
            eyeLabel.contentInsets = UIEdgeInsetsMake(0, 0, 0, 10)
        }
        eyeLabel.contentMode = UIViewContentMode.center
        eyeLabel.font = UIFont(name: kFontAwesomeFont, size: 20)
        eyeLabel.textAlignment = NSTextAlignment.center
        eyeLabel.textColor = UIColor.darkText
        eyeLabel.text = ""
        self.proposedPassword.rightView = eyeLabel
        eyeLabel.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.eyeTap))
        eyeLabel.addGestureRecognizer(tap)
        if #available(iOS 13.0, *) {
            self.isModalInPresentation = true
        }
    }
    
    @objc func eyeTap(sender:UITapGestureRecognizer) {
        let isFirstResponder = eyeLabel.isFirstResponder;
        if (isFirstResponder) { self.eyeLabel.resignFirstResponder() }
        if (self.proposedPassword.isSecureTextEntry) {
            self.eyeLabel.text = ""
        } else {
            self.eyeLabel.text = ""
        }
        self.proposedPassword.isSecureTextEntry.toggle()
        if (isFirstResponder) { self.eyeLabel.becomeFirstResponder() }
    }
    
    @objc func tapScreen(_ sender: UITapGestureRecognizer) {
        self.dismissKeyboard()
    }
    
    func dismissKeyboard() {
        self.proposedPassword.resignFirstResponder()
        self.confirmationCode.resignFirstResponder()
    }
    
    func validateFields() -> Bool {
        self.invalidPasswordLabel.isHidden = true
        self.invalidConfirmationLabel.isHidden = true
        
        var valid = true
        let trimpass = proposedPassword.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimcode = confirmationCode.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if ((trimpass?.isEmpty)! || !(isPasswordValid(trimpass!))) {
            valid = false
            self.invalidPasswordLabel.isHidden = false
        }
        
        if (valid && (trimcode?.isEmpty)!) {
            valid = false
            self.invalidConfirmationLabel.isHidden = false
        }
        
        return valid
    }
    
    func isPasswordValid(_ password: String) -> Bool
    {
        let regularExpression = "^(?=.*?[a-z])(?=.*?[A-Z])(?=.*?[0-9])[A-Za-z0-9$@#!%*?&-_]{8,}$"
        let passwordValidation = NSPredicate.init(format: "SELF MATCHES %@", regularExpression)
        return passwordValidation.evaluate(with: password)
    }
    
    // MARK: - IBActions
    
    @IBAction func updatePassword(_ sender: AnyObject) {
        self.dismissKeyboard()
        
        if (self.validateFields()) {
            let trimcode = confirmationCode.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            //confirm forgot password with input from ui.
            self.user?.confirmForgotPassword(trimcode!, password: self.proposedPassword.text!).continueWith {[weak self] (task: AWSTask) -> AnyObject? in
                guard let strongSelf = self else { return nil }
                DispatchQueue.main.async(execute: {
                    if let error = task.error as NSError? {
                        let alertController = UIAlertController(title: error.userInfo["__type"] as? String,
                                                            message: error.userInfo["message"] as? String,
                                                            preferredStyle: .alert)
                        let okAction = UIAlertAction(title: "Ok", style: .default, handler: nil)
                        alertController.addAction(okAction)
                    
                        self?.present(alertController, animated: true, completion:  nil)
                    } else {
                        let _ = strongSelf.navigationController?.popToRootViewController(animated: true)
                    }
                })
                return nil
            }
        }
    }
    
}

