//
//  OTRComposeGroupViewController.swift
//  ChatSecure
//
//  Created by N-Pex on 2017-08-15.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

import Foundation
import UIKit
import PureLayout

@objc public protocol OTRComposeGroupViewControllerDelegate {
    func groupBuddiesSelected(_ composeViewController: OTRComposeGroupViewController,  buddyUniqueIds:[String], groupName:String) -> Void
    func groupSelectionCancelled(_ composeViewController: OTRComposeGroupViewController) -> Void
}

open class OTRComposeGroupViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITableViewDelegate, UITableViewDataSource, OTRComposeGroupBuddyCellDelegate,OTRYapViewHandlerDelegateProtocol
{
    @objc public weak var delegate:OTRComposeGroupViewControllerDelegate? = nil
    
    @IBOutlet weak var collectionView:UICollectionView!
    @IBOutlet weak var collectionViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var tableView:UITableView!
    @IBOutlet weak var doneButton: UIBarButtonItem!
    
    var viewHandler:OTRYapViewHandler?
    
    var selectedItems:[OTRXMPPBuddy] = []
    var prototypeCell:OTRComposeGroupBuddyCell?
    var existingItems = Set<String>()
    var waitingForExcludedItems = false
    @objc public var groupName:String?
    var publicRoom = false
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        self.automaticallyAdjustsScrollViewInsets = false
        
        let flowLayout = LeftAlignedCollectionViewFlowLayout()
        flowLayout.sectionInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        collectionView.collectionViewLayout = flowLayout
        
        let cellNib = UINib(nibName: "OTRComposeGroupBuddyCell", bundle: Bundle.main)
        self.collectionView.register(cellNib, forCellWithReuseIdentifier: OTRComposeGroupBuddyCell.reuseIdentifier())
        prototypeCell = cellNib.instantiate(withOwner: nil, options: nil)[0] as? OTRComposeGroupBuddyCell
        
        if let connection = OTRDatabaseManager.shared.longLivedReadOnlyConnection {
            self.viewHandler = OTRYapViewHandler(databaseConnection: connection, databaseChangeNotificationName: DatabaseNotificationName.LongLivedTransactionChanges)
            self.viewHandler?.delegate = self
            self.viewHandler?.setup(OTRArchiveFilteredBuddiesName, groups:[OTRBuddyGroup])
        }
        didUpdateCollectionView()
        self.tableView.register(OTRBuddyInfoCheckableCell.self, forCellReuseIdentifier: OTRBuddyInfoCheckableCell.reuseIdentifier())
    }
    
    public func didSetupMappings(_ handler: OTRYapViewHandler) {
        self.tableView?.reloadData()
    }
    
    public func didReceiveChanges(_ handler: OTRYapViewHandler, sectionChanges: [YapDatabaseViewSectionChange], rowChanges: [YapDatabaseViewRowChange]) {
        //TODO: pretty animations
        self.tableView?.reloadData()
    }
    
    open func didUpdateCollectionView() {
        // Layout and resize to match content
        collectionView.setNeedsLayout()
        collectionView.layoutIfNeeded()
        let height = collectionView.contentSize.height
        collectionViewHeightConstraint.constant = height
        if let header = tableView.tableHeaderView {
            let size = header.systemLayoutSizeFitting(UILayoutFittingCompressedSize)
            var frame = header.frame
            frame.size.height = size.height
            header.frame = frame
            tableView.tableHeaderView = header
        }
        
        // Enable/Disable the done button
        self.doneButton.isEnabled = (selectedItems.count > 0)
    }
    
    @IBAction open func didPressDone(_ sender: Any) {
        guard selectedItems.count > 0, let delegate = self.delegate else { return }
        var buddyIds:[String] = []
        //var generatedGroupName = ""
        for buddy in selectedItems {
            buddyIds.append(buddy.uniqueId)
        }
        
        if (groupName == nil) {
            groupName = OTRRoomNames.getRoomName()
        }
        delegate.groupBuddiesSelected(self, buddyUniqueIds: buddyIds, groupName: groupName!)
        groupName = nil;
        dismiss(animated: true, completion: nil)
    }

    open func filterOnAccount(accountUniqueId:String?) {
        // Setup filtering to only show default account!
        OTRDatabaseManager.shared.writeConnection?.readWrite({ (transaction) in
            if let fvt = transaction.ext(OTRArchiveFilteredBuddiesName) as? YapDatabaseFilteredViewTransaction {
                let filtering = YapDatabaseViewFiltering.withObjectBlock { (transaction, group, collection, key, object) -> Bool in
                    if let accountId = accountUniqueId, let buddy = object as? OTRXMPPBuddy {
                        let ret = (buddy.accountUniqueId.caseInsensitiveCompare(accountId) == .orderedSame)
                        return ret
                    }
                    return true
                }
                fvt.setFiltering(filtering, versionTag:NSUUID().uuidString)
            }
        })
    }
    
    open func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return selectedItems.count
    }
    
    open func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        if let cell:OTRComposeGroupBuddyCell = collectionView.dequeueReusableCell(withReuseIdentifier: OTRComposeGroupBuddyCell.reuseIdentifier(), for: indexPath) as? OTRComposeGroupBuddyCell {
            let buddy = selectedItems[indexPath.item]
            cell.bind(buddy: buddy)
            cell.delegate = self
            return cell
        }
        return UICollectionViewCell()
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if let prototype = self.prototypeCell {
            let buddy = selectedItems[indexPath.item]
            prototype.bind(buddy: buddy)
            prototype.setNeedsLayout()
            prototype.layoutIfNeeded()
            let size = prototype.systemLayoutSizeFitting(UILayoutFittingCompressedSize)
            return size
        }
        return CGSize.zero
    }
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return Int(viewHandler?.mappings?.numberOfSections() ?? 0)
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(viewHandler?.mappings?.numberOfItems(inSection: UInt(section)) ?? 0)
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: OTRBuddyInfoCheckableCell.reuseIdentifier(), for: indexPath) as? OTRBuddyInfoCheckableCell,
            let threadOwner = self.viewHandler?.object(indexPath) as? OTRXMPPBuddy {
            var account:OTRAccount? = nil
            var devices:[OMEMODevice] = []
            
            OTRDatabaseManager.shared.uiConnection?.read({ (transaction) in
                if self.shouldShowAccountLabelWithTransaction(transaction: transaction) {
                    account = OTRAccount(forThread: threadOwner, transaction: transaction)
                }
                
                // gray and not selectable if no keys
                devices = OMEMODevice.allDevices(forParentKey: threadOwner.uniqueId, collection: OTRXMPPBuddy.collection, transaction: transaction)
            })
            cell.setThread(threadOwner, account: account)
            cell.setChecked(checked: selectedItems.contains(threadOwner))
            var isExistingOccupant = false
            if existingItems.contains(threadOwner.uniqueId) {
                isExistingOccupant = true
            }
            
            var tColor = UIColor.black
            if #available(iOS 13.0, *) {
                tColor = UIColor.label
            }
            
            cell.nameLabel.textColor = isExistingOccupant ? UIColor.gray : tColor
            cell.accountLabel.textColor = isExistingOccupant ? UIColor.gray : tColor
            cell.identifierLabel.textColor = isExistingOccupant ? UIColor.gray : tColor
            
            if (isExistingOccupant) {
                cell.isUserInteractionEnabled = false
                cell.setChecked(checked: true)
            } else if (devices.count == 0) {
                cell.isUserInteractionEnabled = false
                cell.accountLabel.text = "No secure keys available"
                cell.accountLabel.textColor = UIColor.gray
                cell.nameLabel.textColor = UIColor.gray
            }
            
            return cell
        }
        return UITableViewCell()
    }
    
    open func shouldShowAccountLabelWithTransaction(transaction:YapDatabaseReadTransaction) -> Bool {
        let numberOfAccounts = OTRAccount.numberOfAccounts(with: transaction)
        return (numberOfAccounts > 1 && selectedItems.count < 1)
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return OTRBuddyInfoCellHeight
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if !self.waitingForExcludedItems, let buddy = self.viewHandler?.object(indexPath) as? OTRXMPPBuddy {
            if !selectedItems.contains(buddy) {
                selectedItems.append(buddy)
            } else if let index = selectedItems.index(of: buddy) {
                selectedItems.remove(at: index)
            }
            collectionView.reloadData()
            didUpdateCollectionView()
            tableView.reloadRows(at: [indexPath], with: .automatic)
            updateFiltering()
        }
    }
    
    public func didRemoveBuddy(_ buddy: OTRXMPPBuddy) {
        if let index = selectedItems.index(of: buddy) {
            selectedItems.remove(at: index)
            collectionView.reloadData()
            didUpdateCollectionView()
            updateFiltering()
            tableView.reloadData()
        }
    }

    open func updateFiltering() {
        if (selectedItems.count == 0) {
            filterOnAccount(accountUniqueId: nil)
        } else if (selectedItems.count == 1) {
            filterOnAccount(accountUniqueId: selectedItems[0].accountUniqueId)
        }
    }
    
    open func setExistingRoomOccupants(viewHandler:OTRYapViewHandler?, room:OTRXMPPRoom?) {
        self.waitingForExcludedItems = true
        
        publicRoom = false
        if (room?.isPublic)! {
            publicRoom = true
        }
        
        //query keys 
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            var budjids:[XMPPJID] = []
            if let viewHand = self.viewHandler, let vmappings = viewHand.mappings {
                for section in 0..<vmappings.numberOfSections() {
                    for row in 0..<vmappings.numberOfItems(inSection: section) {
                        if let buddy = viewHand.object(IndexPath(row: Int(row), section: Int(section))) as? OTRXMPPBuddy {
                            OTRDatabaseManager.shared.readConnection?.read({ (transaction) in
                                let devices = OMEMODevice.allDevices(forParentKey: buddy.uniqueId, collection: OTRXMPPBuddy.collection, transaction: transaction)
                                if let bjid = buddy.bareJID, devices.count == 0 {
                                    budjids.append(bjid)
                                }
                            })
                        }
                    }
                }
            }
            
            let accounts = OTRAccountsManager.allAccounts()
            if accounts.count > 0, let xacct = accounts.first as? OTRXMPPAccount, let xmpp = OTRProtocolManager.shared.protocol(for: xacct) as? XMPPManager {
                for (_, item) in budjids.enumerated() {
                    xmpp.omemoSignalCoordinator?.omemoModule?.fetchDeviceIds(for: item, elementId: nil)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.tableView?.reloadData()
            }
        }
        
        DispatchQueue.global().async {
            if let viewHandler = viewHandler, let mappings = viewHandler.mappings {
                for section in 0..<mappings.numberOfSections() {
                    for row in 0..<mappings.numberOfItems(inSection: section) {
                        var buddy:OTRXMPPBuddy? = nil
                        if let roomOccupant = viewHandler.object(IndexPath(row: Int(row), section: Int(section))) as? OTRXMPPRoomOccupant { 
                            OTRDatabaseManager.shared.readConnection?.read({ (transaction) in
                                buddy = roomOccupant.buddy(with: transaction)
                            })
                            if let buddy = buddy {
                                self.existingItems.insert(buddy.uniqueId)
                            }
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                self.waitingForExcludedItems = false
                self.tableView?.reloadData()
            }
        }
    }
    
    // From https://stackoverflow.com/questions/22539979/left-align-cells-in-uicollectionview
    class LeftAlignedCollectionViewFlowLayout: UICollectionViewFlowLayout {
        
        override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
            let attributes = super.layoutAttributesForElements(in: rect)
            
            var leftMargin = sectionInset.left
            var maxY: CGFloat = -1.0
            attributes?.forEach { layoutAttribute in
                if layoutAttribute.frame.origin.y >= maxY {
                    leftMargin = sectionInset.left
                }
                
                layoutAttribute.frame.origin.x = leftMargin
                
                leftMargin += layoutAttribute.frame.width + minimumInteritemSpacing
                maxY = max(layoutAttribute.frame.maxY , maxY)
            }
            
            return attributes
        }
    }
    
    override open func willMove(toParentViewController parent: UIViewController?)
    {
        if parent == nil, let delegate = self.delegate {
            delegate.groupSelectionCancelled(self)
        }
    }
}
