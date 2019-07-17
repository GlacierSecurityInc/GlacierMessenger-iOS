//
//  OTRWelcomeViewController.swift
//  ChatSecure
//
//  Created by Christopher Ballinger on 8/6/15.
//  Copyright (c) 2015 Chris Ballinger. All rights reserved.
//

import UIKit
import OTRAssets

import AWSCognitoIdentityProvider

import AWSCognitoAuth
import AWSS3

open class OTRWelcomeViewController: UIViewController, AWSCognitoAuthDelegate {
    
    // MARK: - Views
    @IBOutlet var logoImageView: UIImageView?
    @IBOutlet var createAccountButton: UIButton?
    @IBOutlet var existingAccountButton: UIButton?
    @IBOutlet var skipButton: UIButton?
    
    @IBOutlet weak var closeBtn: UIButton!
    var canClose: Bool?
    
    @IBOutlet weak var invalidOrgLabel: UILabel!
    @IBOutlet weak var invalidPasswordLabel: UILabel!
    @IBOutlet weak var invalidUsernameLabel: UILabel!
    @IBOutlet weak var usernameField: UITextField!
    @IBOutlet weak var passwordField: UITextField!
    @IBOutlet weak var orgidField: UITextField!
    var cognitoUsername: String?
    var passwordAuthenticationCompletion: AWSTaskCompletionSource<AWSCognitoIdentityPasswordAuthenticationDetails>?
    var newPasswordRequiredCompletionSource: AWSTaskCompletionSource<AWSCognitoIdentityNewPasswordRequiredDetails>?
    
    let awsAccountMgr = AWSAccountManager.shared
    var ssoUsed = false
    var vSpinner : UIView?
    
    // MARK: - View Lifecycle
    
    override open func viewWillAppear(_ animated: Bool) {
        self.navigationController!.setNavigationBarHidden(true, animated: animated)
        self.resetFields()
    }
    
    override open func viewWillDisappear(_ animated: Bool) {
        self.stopSpinner()
        self.navigationController!.setNavigationBarHidden(false, animated: animated)
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()

        self.createAccountButton?.setTitle(CREATE_NEW_ACCOUNT_STRING(), for: .normal)
        self.skipButton?.setTitle(SKIP_STRING(), for: .normal)
        self.existingAccountButton?.setTitle(ADD_EXISTING_STRING(), for: .normal)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.tapScreen(_:)))
        self.view.addGestureRecognizer(tapGesture)
        self.invalidUsernameLabel.isHidden = true
        self.invalidOrgLabel.isHidden = true
        self.invalidPasswordLabel.isHidden = true
        
        if let closeable = canClose {
            self.closeBtn.isEnabled = closeable
            self.closeBtn.isHidden = !closeable
        }
        
        awsAccountMgr.setAuthenticator(self)
    }

    override open func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    
    // MARK: - Navigation
    override open func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let loginVC = segue.destination as? OTRBaseLoginViewController else {
            return
        }
        if segue.identifier == "createNewAccountSegue" {
            loginVC.form = XLFormDescriptor.registerNewAccountForm(with: .jabber)
            loginVC.loginHandler = OTRXMPPCreateAccountHandler()
        } else if segue.identifier == "addExistingAccount" {
            loginVC.form = XLFormDescriptor.existingAccountForm(with: .jabber)
            loginVC.loginHandler = OTRXMPPLoginHandler()
        } else if segue.identifier == "AddAccountSegue" {
            viewWillAppear(false)
            loginVC.form = XLFormDescriptor.existingAccountForm(with: .jabber)
            loginVC.showsCancelButton = true;
            loginVC.loginHandler = OTRXMPPLoginHandler()
        }
    }
    
    @IBAction func skipButtonPressed(_ sender: AnyObject) {
        self.dismiss(animated: true, completion: nil)
    }

    @objc public func displayCloseFunction(_ closeable: Bool) {
        self.canClose = closeable
    }
    
    @objc public func startSpinner() {
        self.showSpinner(onView: self.view)
    }
    
    @objc public func stopSpinner() {
        self.removeSpinner()
    }
    
    @IBAction func usessoPressed(_ sender: Any) {
        self.dismissKeyboard()
        self.ssoUsed = true
        self.awsAccountMgr.handleSSO()
    }
    
    public func getViewController() -> UIViewController {
        return self;
    }
    
    @IBAction func loginPressed(_ sender: Any) {
        self.dismissKeyboard()
        
        if (self.validateFields()) {
            
            self.ssoUsed = false
            awsAccountMgr.setupCognito()
            awsAccountMgr.getUserDetails()
            
            let trimuser = usernameField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimpass = passwordField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimorg = orgidField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let glacierDefaults = UserDefaults(suiteName: "group.com.glaciersec.apps")
            glacierDefaults?.set(trimorg, forKey: "orgid")
            glacierDefaults?.synchronize()
            
            if (trimorg == "apple" || trimorg == "Apple") { 
                glacierDefaults?.set(trimuser, forKey: "username")
                glacierDefaults?.set(trimpass, forKey: "password")
                glacierDefaults?.set(true, forKey: "altroute")
                glacierDefaults?.synchronize()
                self.dismiss(animated: true, completion: nil)
            } else {
                if (!awsAccountMgr.coreSignedIn()) {
                    let authDetails = AWSCognitoIdentityPasswordAuthenticationDetails(username: trimuser!, password: trimpass!)
                    self.passwordAuthenticationCompletion?.set(result: authDetails)
                }
            }
        }
    }
    
    func resetFields() {
        let glacierDefaults = UserDefaults(suiteName: "group.com.glaciersec.apps")
        let orgid = glacierDefaults?.string(forKey: "orgid")
        if (orgid != nil) {
            orgidField.text = orgid;
        }
        
        if (self.cognitoUsername != nil) {
            usernameField.text = self.cognitoUsername;
        }
    }
    
    @objc func tapScreen(_ sender: UITapGestureRecognizer) {
        self.dismissKeyboard()
    }
    
    func dismissKeyboard() {
        self.passwordField.resignFirstResponder()
        self.usernameField.resignFirstResponder()
        self.orgidField.resignFirstResponder()
    }
    
    func validateFields() -> Bool {
        var valid = true
        
        if ((self.usernameField.text?.isEmpty)!) {
            valid = false
            self.invalidUsernameLabel.isHidden = false
        } else {
            self.invalidUsernameLabel.isHidden = true
        }
        
        if ((self.passwordField.text?.isEmpty)!) {
            valid = false
            self.invalidPasswordLabel.isHidden = false
        } else {
            self.invalidPasswordLabel.isHidden = true
        }
        
        if ((self.orgidField.text?.isEmpty)!) {
            valid = false
            self.invalidOrgLabel.isHidden = false
        } else {
            self.invalidOrgLabel.isHidden = true
        }
        
        return valid
    }
}

extension OTRWelcomeViewController: AWSCognitoIdentityPasswordAuthentication {
    
    public func getDetails(_ authenticationInput: AWSCognitoIdentityPasswordAuthenticationInput, passwordAuthenticationCompletionSource: AWSTaskCompletionSource<AWSCognitoIdentityPasswordAuthenticationDetails>) {
        self.passwordAuthenticationCompletion = passwordAuthenticationCompletionSource
        DispatchQueue.main.async {
            if(self.cognitoUsername == nil && !self.ssoUsed) {
                self.cognitoUsername = authenticationInput.lastKnownUsername;
            }
        }
    }
    
    public func didCompleteStepWithError(_ error: Error?) {
        DispatchQueue.main.async {
            if let error = error as NSError? {
                self.removeSpinner()
                let alertController = UIAlertController(title: nil,
                                                        message: error.userInfo["message"] as? String,
                                                        preferredStyle: .alert)
                let cancelAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
                alertController.addAction(cancelAction)
                self.present(alertController, animated: true, completion:  nil)
            } else {
                self.cognitoUsername = nil;
            }
        }
    }
}

extension OTRWelcomeViewController {
    func showSpinner(onView : UIView) {
        DispatchQueue.main.async {
            let spinnerView = UIView.init(frame: onView.bounds)
            spinnerView.backgroundColor = UIColor.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
            let ai = UIActivityIndicatorView.init(activityIndicatorStyle: .whiteLarge)
            ai.startAnimating()
            ai.center = spinnerView.center
        
            spinnerView.addSubview(ai)
            onView.addSubview(spinnerView)
            
            self.vSpinner = spinnerView
        }
    }
    
    func removeSpinner() {
        DispatchQueue.main.async {
            self.vSpinner?.removeFromSuperview()
            self.vSpinner = nil
        }
    }
}
