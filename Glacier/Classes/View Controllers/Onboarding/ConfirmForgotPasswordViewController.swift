//
//  ConfirmForgotPasswordViewController.swift
//  Created on 12/16/19.
//  Copyright © 2019 Glacier Security. All rights reserved.
//

import Foundation

class ConfirmForgotPasswordViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    // MARK: - IBActions
    //Removed all functional code because we are now handling it via console
    @IBAction func updatePassword(_ sender: AnyObject) {
        self.navigationController?.popToRootViewController(animated: true)
    }
}

