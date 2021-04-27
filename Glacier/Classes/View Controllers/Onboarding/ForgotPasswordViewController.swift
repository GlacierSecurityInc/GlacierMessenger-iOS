//
//  ForgotPasswordViewController.swift
//  Created on 12/16/19.
//  Copyright © 2019 Glacier Security. All rights reserved.

import Foundation
import UIKit
import AWSCognitoIdentityProvider

import SAMKeychain;

open class ForgotPasswordViewController: UIViewController {
    
    @IBOutlet weak var usernameLabel: UILabel!
    @IBOutlet weak var forgotPasswordButton: UIButton!
    @IBOutlet weak var usernameInput: UITextField!
    @IBOutlet weak var invalidUsernameLabel: UILabel!
    
    var pool: AWSCognitoIdentityUserPool?
    var user: AWSCognitoIdentityUser?
    
    var currentUserAttributes:[String:String]?
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        self.pool = AWSCognitoIdentityUserPool.default()
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.tapScreen(_:)))
        self.view.addGestureRecognizer(tapGesture)
        self.invalidUsernameLabel.isHidden = true
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.usernameInput.text = nil
        self.navigationController?.setNavigationBarHidden(false, animated: false)
    }
    
    override open func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        //if let newPasswordViewController = segue.destination as? ConfirmForgotPasswordViewController {
        //    newPasswordViewController.user = self.user
        //}
    }
    
    @IBAction func forgotPasswordPressed(_ sender: Any) {
        self.dismissKeyboard()
        
        if (self.validateFields()) {
            let trimuser = usernameInput.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            self.user = self.pool?.getUser(trimuser!)
            self.user?.forgotPassword().continueWith{[weak self] (task: AWSTask) -> AnyObject? in
                guard let strongSelf = self else {return nil}
                DispatchQueue.main.async(execute: {
                    if (task.error as NSError?) != nil {
                        let alertController = UIAlertController(title: "Cannot Reset Password", message: "There is no email or phone associated with this account, so you will need to contact Glacier support to reset password.", preferredStyle: UIAlertControllerStyle.alert)
                        
                        // Replace UIAlertActionStyle.Default by UIAlertActionStyle.default
                        let okAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.default) {
                            (result : UIAlertAction) -> Void in
                            self?.navigationController?.popViewController(animated: true)
                        }
                        alertController.addAction(okAction)
                        self?.present(alertController, animated: true, completion: nil)
                    } else {
                        strongSelf.performSegue(withIdentifier: "confirmForgotPasswordSegue", sender: sender)
                    }
                })
                return nil
            }
        }
    }
    
    @objc func tapScreen(_ sender: UITapGestureRecognizer) {
        self.dismissKeyboard()
    }
    
    func dismissKeyboard() {
        self.usernameInput.resignFirstResponder()
    }
    
    func validateFields() -> Bool {
        self.invalidUsernameLabel.isHidden = true
        
        var valid = true
        let trimuser = usernameInput.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if ((trimuser?.isEmpty)!) {
            valid = false
            self.invalidUsernameLabel.isHidden = false
        }
        
        return valid
    }
}
