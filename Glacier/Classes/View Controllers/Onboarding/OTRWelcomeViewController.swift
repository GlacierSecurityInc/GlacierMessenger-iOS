//
//  OTRWelcomeViewController.swift
//  ChatSecure
//
//  Created by Christopher Ballinger on 8/6/15.
//  Copyright (c) 2015 Chris Ballinger. All rights reserved.
//

import UIKit
import AWSCognitoIdentityProvider
import AWSCognitoAuth
import AWSS3
import SAMKeychain;

open class OTRWelcomeViewController: UIViewController, AWSCognitoAuthDelegate {
    
    // MARK: - Views
    @IBOutlet var logoImageView: UIImageView?
    @IBOutlet var createAccountButton: UIButton?
    @IBOutlet var existingAccountButton: UIButton?
    @IBOutlet var skipButton: UIButton?
    
    @IBOutlet weak var versionLabel: UILabel!
    @IBOutlet weak var closeBtn: UIButton!
    var canClose: Bool?
    
    @IBOutlet weak var invalidPasswordLabel: UILabel!
    @IBOutlet weak var invalidUsernameLabel: UILabel!
    @IBOutlet weak var usernameField: UITextField!
    @IBOutlet weak var passwordField: UITextField!
    var cognitoUsername: String?
    var passwordAuthenticationCompletion: AWSTaskCompletionSource<AWSCognitoIdentityPasswordAuthenticationDetails>?
    var newPasswordRequiredCompletionSource: AWSTaskCompletionSource<AWSCognitoIdentityNewPasswordRequiredDetails>?
    
    let awsAccountMgr = AWSAccountManager.shared
    var ssoUsed = false
    var vSpinner : UIView?
    
    let eyeLabel = InsetsLabel(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
    
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
        
        setupVersionLabel()
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.tapScreen(_:)))
        self.view.addGestureRecognizer(tapGesture)
        self.invalidUsernameLabel.isHidden = true
        self.invalidPasswordLabel.isHidden = true
        
        self.passwordField.rightViewMode = UITextFieldViewMode.always
        if #available(iOS 13.0, *) {
            eyeLabel.contentInsets = UIEdgeInsetsMake(0, 0, 0, 10)
        }
        eyeLabel.contentMode = UIViewContentMode.center
        eyeLabel.font = UIFont(name: kFontAwesomeFont, size: 20)
        eyeLabel.textAlignment = NSTextAlignment.center
        eyeLabel.textColor = UIColor.darkText
        eyeLabel.text = ""
        self.passwordField.rightView = eyeLabel
        eyeLabel.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.eyeTap))
        eyeLabel.addGestureRecognizer(tap)
        if #available(iOS 13.0, *) {
            self.isModalInPresentation = true
        }
        
        awsAccountMgr.setAuthenticator(self)
        
        if let closeable = canClose, let _ = self.closeBtn {
            self.closeBtn.isEnabled = closeable
            self.closeBtn.isHidden = !closeable
        }
    }
    
    func setupVersionLabel() {
        if let info = Bundle.main.infoDictionary, let appVersion = info["CFBundleShortVersionString"] as? String, let appBuild = info[kCFBundleVersionKey as String] as? String {
            let versionTitle = String(format: "%@ %@ (%@)", VERSION_STRING(), appVersion, appBuild)
            versionLabel.text = versionTitle
        }
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
        if segue.identifier == "addExistingAccount" {
            loginVC.form = XLFormDescriptor.existingAccountForm(with: .jabber)
            loginVC.loginHandler = OTRXMPPLoginHandler()
        } else if segue.identifier == "AddAccountSegue" {
            viewWillAppear(false)
            loginVC.form = XLFormDescriptor.existingAccountForm(with: .jabber)
            loginVC.showsCancelButton = true;
            loginVC.loginHandler = OTRXMPPLoginHandler()
        }
    }
    
    @objc func eyeTap(sender:UITapGestureRecognizer) {
        let isFirstResponder = eyeLabel.isFirstResponder;
        if (isFirstResponder) { self.eyeLabel.resignFirstResponder() }
        if (self.passwordField.isSecureTextEntry) {
            self.eyeLabel.text = ""
        } else {
            self.eyeLabel.text = ""
        }
        self.passwordField.isSecureTextEntry = !self.passwordField.isSecureTextEntry
        if (isFirstResponder) { self.eyeLabel.becomeFirstResponder() }
    }
    
    @IBAction func skipButtonPressed(_ sender: AnyObject) {
        self.dismiss(animated: true, completion: nil)
    }

    @objc public func displayCloseFunction(_ closeable: Bool) {
        self.canClose = closeable
        if let closeable = canClose, let _ = self.closeBtn { 
            self.closeBtn.isEnabled = closeable
            self.closeBtn.isHidden = !closeable
        }
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
    
    @IBAction func supportPressed(_ sender: Any) {
        if let supportUrl = URL(string: "https://glacier.chat/support") {
            UIApplication.shared.open(supportUrl, options: [:], completionHandler: nil)
        }
    }
    
    @IBAction func forgotPasswordPressed(_ sender: Any) {
        
    }
    
    @IBAction func createTeam(_ sender: Any) {
        if let url = URL(string: "https://glacier.chat/product#signup") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
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
            
            if (!awsAccountMgr.coreSignedIn()) {
                if let cpass = trimpass, let cuser = trimuser {
                    let userid = NSUUID().uuidString
                    let idresult = SAMKeychain.setPassword(userid, forService:kGlacierGroup, account:kCognitoAcct, accessGroup:kGlacierGroup, error: nil)
                    let result = SAMKeychain.setPassword(cpass, forService:kGlacierGroup, account:userid, accessGroup:kGlacierGroup, error: nil)
                    //GlacierLog.glog(logMsg:"Setting cognito password", detail: userid) 
                    if (!result || !idresult) {
                        DDLogError("Error saving id or password to keychain: \(cuser)")
                        //GlacierLog.glog(logMsg:"Error saving cognito password", detail: userid)
                    }
                }
                    
                let authDetails = AWSCognitoIdentityPasswordAuthenticationDetails(username: trimuser!, password: trimpass!)
                self.passwordAuthenticationCompletion?.set(result: authDetails)
            }
        }
    }
    
    func resetFields() {
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
