//
//  OTRSplitViewCoordinator.swift
//  ChatSecure
//
//  Created by David Chiles on 11/30/15.
//  Copyright © 2015 Chris Ballinger. All rights reserved.
//

import Foundation
import OTRAssets

open class OTRSplitViewCoordinator: NSObject, OTRConversationViewControllerDelegate, OTRComposeViewControllerDelegate, OTRComposeGroupViewControllerDelegate {
    
    @objc open weak var splitViewController:UISplitViewController? = nil
    
    @objc public init(databaseConnection:YapDatabaseConnection) {
        //
    }
    
    open func enterConversationWithBuddies(_ buddyKeys:[String], accountKey:String, name:String?) {
        guard let splitVC = self.splitViewController else {
            return
        }
        
        if let appDelegate = UIApplication.shared.delegate as? OTRAppDelegate {
            let messagesVC = appDelegate.messagesViewController
            messagesVC.setup(withBuddies: buddyKeys, accountId: accountKey, name:name)
            //setup 'back' button in nav bar
            let navigationController = UINavigationController(rootViewController: messagesVC)
            navigationController.topViewController!.navigationItem.leftBarButtonItem = splitVC.displayModeButtonItem;
            navigationController.topViewController!.navigationItem.leftItemsSupplementBackButton = true;
            splitVC.showDetailViewController(navigationController, sender: nil)
        }
    }
    
    public func enterPublicConversation(withName name:String) {
        guard let splitVC = self.splitViewController else {
            return
        }
        
        if let appDelegate = UIApplication.shared.delegate as? OTRAppDelegate {
            let messagesVC = appDelegate.messagesViewController
            messagesVC.setupPublicGroup(withName:name)
            //setup 'back' button in nav bar
            let navigationController = UINavigationController(rootViewController: messagesVC)
            navigationController.topViewController!.navigationItem.leftBarButtonItem = splitVC.displayModeButtonItem;
            navigationController.topViewController!.navigationItem.leftItemsSupplementBackButton = true;
            splitVC.showDetailViewController(navigationController, sender: nil)
        }
    }
    
    open func enterConversationWithBuddy(_ buddyKey:String) {
        var buddy:OTRThreadOwner? = nil
        
        OTRDatabaseManager.shared.readConnection?.read { (transaction) -> Void in
            buddy = OTRBuddy.fetchObject(withUniqueID: buddyKey, transaction: transaction)
        }
        if let b = buddy {
            self.enterConversationWithThread(b, sender: nil)
        }
    }
    
    @objc open func enterConversationWithThread(_ threadOwner:OTRThreadOwner, sender:AnyObject?) {
        guard let splitVC = self.splitViewController else {
            return
        }
        
        let appDelegate = UIApplication.shared.delegate as? OTRAppDelegate
        
        let messagesViewController:OTRMessagesViewController? = appDelegate?.messagesViewController
        guard let mVC = messagesViewController else {
            return
        }
        
        OTRProtocolManager.encryptionManager.maybeRefreshOTRSession(forBuddyKey: threadOwner.threadIdentifier, collection: threadOwner.threadCollection)
        
        //Set nav controller root view controller to mVC and then show detail with nav controller
        
        mVC.setThreadKey(threadOwner.threadIdentifier, collection: threadOwner.threadCollection)
        
        //iPad check where there are two navigation controllers and we want the second one
        if splitVC.viewControllers.count > 1 && ((splitVC.viewControllers[1] as? UINavigationController)?.viewControllers.contains(mVC)) ?? false {
        } else if splitVC.viewControllers.count == 1 && ((splitVC.viewControllers.first as? UINavigationController)?.viewControllers.contains(mVC)) ?? false {
        } else {
            splitVC.showDetailViewController(mVC, sender: sender)
        }
    }
    
    //MARK: OTRConversationViewControllerDelegate Methods
    public func conversationViewController(_ conversationViewController: OTRConversationViewController!, didSelectThread threadOwner: OTRThreadOwner!) {
        self.enterConversationWithThread(threadOwner, sender: conversationViewController)
    }
    
    public func conversationViewController(_ conversationViewController: OTRConversationViewController!, didSelectCompose sender: Any!) {
        let composeViewController = GlobalTheme.shared.composeViewController()
        if let composeViewController = composeViewController as? OTRComposeViewController {
            composeViewController.delegate = self
        }
        let modalNavigationController = UINavigationController(rootViewController: composeViewController)
        modalNavigationController.modalPresentationStyle = .formSheet
        
        //May need to use conversationViewController
        self.splitViewController?.present(modalNavigationController, animated: true, completion: nil)
    }
    
    public func conversationViewController(_ conversationViewController: OTRConversationViewController!, didSelectDialpad sender: Any!) {
        goGlacierVoice()
    }
    
    // tries to open Glacier Voice or notifies user if can't
    private func goGlacierVoice() {
        let voiceHooks = "glaciervoice://"
        let voiceUrl = NSURL(string: voiceHooks)
        if UIApplication.shared.canOpenURL(voiceUrl! as URL)
        {
            UIApplication.shared.openURL(voiceUrl! as URL)
            
        } else {
            let alertController = UIAlertController(title: "Glacier Voice not installed", message: "Install Glacier Voice from the App Store", preferredStyle: UIAlertControllerStyle.alert)
            
            // Replace UIAlertActionStyle.Default by UIAlertActionStyle.default
            let okAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.default) {
                (result : UIAlertAction) -> Void in
                print("OK")
            }
            alertController.addAction(okAction)
            self.splitViewController?.present(alertController, animated: true, completion: nil)
        }
    }
    
    //modified to go to OTRComposeGroupViewController
    public func conversationViewController(_ conversationViewController: OTRConversationViewController!, didSelectGroup sender: Any!) {
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = NSTextAlignment.left
        let messageText = NSMutableAttributedString(
            string: "\nOpen groups have no user limit and store group chat history\n\nInvite only groups have a 20 user recommended limit and are managed by the owner",
            attributes: [
                NSAttributedStringKey.paragraphStyle: paragraphStyle,
                NSAttributedStringKey.font: UIFont.preferredFont(forTextStyle: UIFontTextStyle.footnote),
                NSAttributedStringKey.foregroundColor: UIColor.black
            ]
        )
        
        let alert = UIAlertController(title: NSLocalizedString("New Group", comment: "Type of group"), message: "\nOpen groups have no user limit and store group chat history\n\nInvite only groups have a 20 user recommended limit and are managed by the owner", preferredStyle: UIAlertControllerStyle.alert)
        alert.setValue(messageText, forKey: "attributedMessage")
        alert.addAction(UIAlertAction(title: NSLocalizedString("Invite Only", comment: "Invite Only button"), style: UIAlertActionStyle.default, handler: {(action: UIAlertAction!) in
            let assets = OTRAssets.resourcesBundle
            let storyboard = UIStoryboard(name: "OTRComposeGroup", bundle: assets)
            guard let vc = storyboard.instantiateInitialViewController() else { return }
            
            if let composeGroupViewController = vc as? OTRComposeGroupViewController {
                composeGroupViewController.delegate = self;
                let firstTextField = alert.textFields![0] as UITextField
                var name = firstTextField.placeholder
                if ((firstTextField.text?.count)! > 1) {
                    name = firstTextField.text
                }
                composeGroupViewController.groupName = name
                let modalNavigationController = UINavigationController(rootViewController: composeGroupViewController)
                let leftBarButton = UIBarButtonItem(title: "Cancel", style: UIBarButtonItemStyle.plain, target: self, action: #selector(self.groupSelectionCancelled(_:)))
                composeGroupViewController.navigationItem.leftBarButtonItem = leftBarButton
                modalNavigationController.navigationBar.tintColor = UIColor.black
                modalNavigationController.modalPresentationStyle = .formSheet
                self.splitViewController?.present(modalNavigationController, animated: true, completion: nil)
            }
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Open", comment: "Open Group button"), style: UIAlertActionStyle.default, handler: {(action: UIAlertAction!) in
            let firstTextField = alert.textFields![0] as UITextField
            var name = firstTextField.placeholder
            if ((firstTextField.text?.count)! > 1) {
                name = firstTextField.text
            }
            self.enterPublicConversation(withName:name!)
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: UIAlertActionStyle.cancel, handler: nil))
        alert.addTextField(configurationHandler: {(textField: UITextField!) in
            textField.placeholder = OTRRoomNames.getRoomName()
            textField.isSecureTextEntry = false
        })
        self.splitViewController?.present(alert, animated: true, completion: nil)
    }
    
    //MARK:  OTRComposeGroupViewControllerDelegate
    public func groupSelectionCancelled(_ composeViewController: OTRComposeGroupViewController) {
        self.splitViewController?.dismiss(animated: true, completion: nil)
    }
    
    public func groupBuddiesSelected(_ composeViewController: OTRComposeGroupViewController, buddyUniqueIds: [String], groupName: String) {
        
        var accountId:String? = nil
        OTRDatabaseManager.shared.readConnection?.read { (transaction) -> Void in
            
            let randomItem = Int(arc4random() % UInt32(buddyUniqueIds.count))
            let buddyKey = buddyUniqueIds[randomItem]
            
            accountId = (OTRBuddy.fetchObject(withUniqueID: buddyKey, transaction: transaction))?.accountUniqueId
        }
        
        func doClose () -> Void {
            let buds = buddyUniqueIds
            guard let accountKey = accountId else {
                return
            }
            
            if (buds.count == 1) {
                if let key = buds.first {
                    self.enterConversationWithBuddy(key)
                }
            } else if (buds.count > 1) {
                self.enterConversationWithBuddies(buds, accountKey: accountKey, name:groupName)
            }
        }
        
        
        if (self.splitViewController?.presentedViewController == composeViewController.navigationController) {
            self.splitViewController?.dismiss(animated: true) { doClose() }
        } else {
            doClose()
        }
    }
    
    //MARK: OTRComposeViewControllerDelegate Methods
    open func controller(_ viewController: OTRComposeViewController, didSelectBuddies buddies: [String]?, accountId: String?, name: String?) {

        func doClose () -> Void {
            guard let buds = buddies,
                let accountKey = accountId else {
                    return
            }
            
            if (buds.count == 1) {
                if let key = buds.first {
                    self.enterConversationWithBuddy(key)
                }
            } else if (buds.count > 1) {
                self.enterConversationWithBuddies(buds, accountKey: accountKey, name:name)
            }
        }

        
        if (self.splitViewController?.presentedViewController == viewController.navigationController) {
            self.splitViewController?.dismiss(animated: true) { doClose() }
        } else {
            doClose()
        }
    }
    
    open func controllerDidCancel(_ viewController: OTRComposeViewController) {
        self.splitViewController?.dismiss(animated: true, completion: nil)
    }
    
    @objc open func showConversationsViewController() {
        if self.splitViewController?.presentedViewController != nil {
            self.splitViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc open func showAccountDetails(account: OTRXMPPAccount, completion: (()->Void)?) {
        guard splitViewController?.presentedViewController == nil else {
            return
        }
        
        let detailVC = GlobalTheme.shared.accountDetailViewController(account: account)
        
        let nav = UINavigationController(rootViewController: detailVC)
        nav.modalPresentationStyle = .formSheet
        splitViewController?.present(nav, animated: true, completion: completion)
    }
}

open class OTRSplitViewControllerDelegateObject: NSObject, UISplitViewControllerDelegate {
    
    open func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        
        return true
    }

    
}
