//
//  SideMenuView.swift
//  ChatSecureCore
//
//  Created by Andy Friedman on 2/1/18.

import UIKit
import OTRAssets

@objc public protocol SideMenuDelegate: class {
    @objc func addVPNConnection()
    @objc func gotoSettings()
    @objc func gotoSupport()
    @objc func closingSideMenu()
}


public class SideMenuView: UIView {
    
    @objc @IBOutlet public weak var displayNameLabel: UILabel!
    @objc @IBOutlet public weak var accountNameLabel: UILabel!
    @objc public weak var delegate: SideMenuDelegate?
    @objc @IBOutlet public weak var topConstraint: NSLayoutConstraint!
    @objc @IBOutlet public weak var frontConstraint: NSLayoutConstraint!
    
    @IBAction func addVPNConnection(_ sender: Any) {
        tapMenuAction(sender)
        delegate?.addVPNConnection()
    }
    
    @IBAction func goToSettings(_ sender: Any) {
        tapMenuAction(sender)
        delegate?.gotoSettings()
    }
    
    @IBAction func gotoSupport(_ sender: Any) {
        tapMenuAction(sender)
        delegate?.gotoSupport()
    }
    
    @IBAction func tapMenuAction(_ sender: Any) {
        delegate?.closingSideMenu()
    }
}
