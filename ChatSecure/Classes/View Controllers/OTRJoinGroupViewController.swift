//
//  OTRJoinGroupViewController.swift
//  ChatSecureCore
//
//  Created by Andy Friedman on 11/8/17.
//  Copyright © 2017 Glacier Security, Inc. All rights reserved.
//
import Foundation
import UIKit
import PureLayout
import OTRAssets

@objc public protocol OTRJoinGroupViewControllerDelegate {
    func groupSelected(_ composeViewController: OTRJoinGroupViewController, groupName:String) -> Void
    func joinGroupCancelled(_ composeViewController: OTRJoinGroupViewController) -> Void
}

open class OTRJoinGroupViewController: UIViewController, UITableViewDelegate, UITableViewDataSource
{
    @objc public weak var delegate:OTRJoinGroupViewControllerDelegate? = nil
    @IBOutlet weak var tableView:UITableView!
    
    var existingItems = Set<String>()
    
    var cellData:[String] = [];
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        let accounts = OTRAccountsManager.allAccounts()
        if (accounts.count > 0) {
            let account = accounts[0]
            let xmpp = OTRProtocolManager.shared.protocol(for: account) as? OTRXMPPManager
            if (xmpp != nil) {
                if let tempData = xmpp?.roomManager.availableRooms {
                    for gname in tempData {
                        //check if room already joined?
                        
                        if let range = gname.range(of: "@") {
                            let slimname = String(gname[..<range.lowerBound])
                            cellData.append(slimname)
                        }
                    }
                }
            }
        }
        
        if (cellData.count < 1) {
            cellData.append("No rooms to join")
        }
        
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "groupname")
    }
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return cellData.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = self.tableView.dequeueReusableCell(withIdentifier: "groupname") {
            cell.textLabel?.text = self.cellData[indexPath.row]
            return cell
        }
        return UITableViewCell()
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return OTRBuddyInfoCellHeight
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let gname = self.cellData[indexPath.row] as String
        if (gname.hasPrefix("No rooms")) {
            dismiss(animated: true, completion: nil)
        }
        
        if let delegate = delegate {
            delegate.groupSelected(self, groupName: gname)
        }
        dismiss(animated: true, completion: nil)
    }
    
    override open func willMove(toParentViewController parent: UIViewController?)
    {
        if parent == nil, let delegate = self.delegate {
            delegate.joinGroupCancelled(self)
        }
    }
}

