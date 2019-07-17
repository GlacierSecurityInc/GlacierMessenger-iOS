//
//  RoomAttachmentsViewController.swift
//  ChatSecureCore
//
//  Created by Andy Friedman on 5/8/19.
//  Copyright © 2019 Glacier Security. All rights reserved.

import Foundation
import UIKit
import PureLayout
import BButton
import OTRAssets
import MobileCoreServices
//import WebKit
import MBProgressHUD

private struct CellIdentifier {
    /// Storyboard Cell Identifiers
    static let HeaderCellGroupName = StoryboardCellIdentifier.groupName.rawValue
    static let HeaderCellAddAttachment = StoryboardCellIdentifier.addAttachments.rawValue
    static let HeaderCellAttachments = StoryboardCellIdentifier.attachments.rawValue
}

/// Cell identifiers only used in code
private enum DynamicCellIdentifier: String {
    case attachment = "attachment"
}

/// Cell identifiers from the RoomAttachments.storyboard
private enum StoryboardCellIdentifier: String {
    case groupName = "cellGroupName"
    case addAttachments = "cellGroupAddAttachments"
    case attachments = "cellGroupAttachments"
}

private class GenericHeaderCell: UITableViewCell {
    static let cellHeight: CGFloat = 44
    override func prepareForReuse() {
        super.prepareForReuse()
        textLabel?.text = nil
        accessoryView = nil
    }
}

private enum GroupName: String {
    case header = "UITableViewSectionHeader"
}

private let GroupNameHeader = GroupName.header.rawValue

open class RoomAttachmentsViewController: UIViewController {
    
    @IBOutlet open weak var tableView:UITableView!
    @IBOutlet weak var largeAvatarView:UIImageView!
    
    let disabledCellAlphaValue:CGFloat = 0.5
    
    // For matching navigation bar and avatar
    var navigationBarShadow:UIImage?
    var navigationBarBackground:UIImage?
    var topBounceView:UIView?

    var roomAttachments:[String] = []
    open var roomUniqueId: String?
    open var pins: XMPPPinned?
    //var vSpinner : UIView?
    
    /// opens implicit db transaction
    open var room:OTRXMPPRoom? {
        return connections?.ui.fetch { self.room($0) }
    }
    
    private func room(_ transaction: YapDatabaseReadTransaction) -> OTRXMPPRoom? {
        guard let roomUniqueId = self.roomUniqueId else {
            return nil
        }
        return OTRXMPPRoom.fetchObject(withUniqueID: roomUniqueId, transaction: transaction)
    }
    
    open var headerRows:[String] = []
    
    /// for reads only
    fileprivate let readConnection = OTRDatabaseManager.shared.uiConnection
    /// for reads and writes
    private let connections = OTRDatabaseManager.shared.connections
    
    
    @objc public init(roomKey:String, pinned:XMPPPinned) {
        super.init(nibName: nil, bundle: nil)
        setupRoom(roomKey: roomKey, pinned: pinned)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    @objc public func setupRoom(roomKey:String, pinned:XMPPPinned?) {
        self.roomUniqueId = roomKey
        self.pins = pinned
        roomAttachments = []
        if let links = self.pins?.pinnedURLs {
            for pin in links {
                roomAttachments.append(pin)
            }
        }
        
        guard let _ = self.room else {
            return
        }
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        headerRows = [
            CellIdentifier.HeaderCellGroupName,
            CellIdentifier.HeaderCellAddAttachment,
            CellIdentifier.HeaderCellAttachments
        ]
        
        if let room = self.room {
            let seedNum = room.avatarSeedNum
            let image = OTRGroupAvatarGenerator.avatarImage(withSeedNum: seedNum, width: Int(largeAvatarView.frame.width), height: Int(largeAvatarView.frame.height))
            largeAvatarView.image = image
        }
        
        
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: DynamicCellIdentifier.attachment.rawValue)
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == self.tableView {
            // Adjust the frame of the overscroll view
            if let topBounceView = self.topBounceView {
                let frame = CGRect(x: 0, y: 0, width: self.tableView.frame.size.width, height: self.tableView.contentOffset.y)
                topBounceView.frame = frame
            }
        }
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Store shadow and background, so we can restore them
        self.navigationBarShadow = self.navigationController?.navigationBar.shadowImage
        self.navigationBarBackground = self.navigationController?.navigationBar.backgroundImage(for: .default)
        
        // Make the navigation bar the same color as the top color of the avatar image
        self.navigationController?.navigationBar.shadowImage = UIImage()
        self.navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        if self.room != nil {
            self.navigationController?.navigationBar.barTintColor = UIColor.white
            
            // Create a view for the bounce background, with same color as the topmost
            // avatar color.
            if self.topBounceView == nil {
                self.topBounceView = UIView()
                if let view = self.topBounceView {
                    view.backgroundColor = UIColor.white
                    self.tableView.addSubview(view)
                }
            }
        }
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        //self.stopSpinner()
        
        // Restore navigation bar
        self.navigationController?.navigationBar.barTintColor = UINavigationBar.appearance().barTintColor
        self.navigationController?.navigationBar.shadowImage = self.navigationBarShadow
        self.navigationController?.navigationBar.setBackgroundImage(self.navigationBarBackground, for: .default)
    }
    
    open func createHeaderCell(type:String, at indexPath: IndexPath) -> UITableViewCell {
        var _cell: UITableViewCell?
        if DynamicCellIdentifier(rawValue: type) != nil {
            _cell = tableView.dequeueReusableCell(withIdentifier: type, for: indexPath)
        } else {
            // storyboard cell
            _cell = tableView.dequeueReusableCell(withIdentifier: type)
        }
        
        guard let cell = _cell else { return UITableViewCell() }
        switch type {
        case CellIdentifier.HeaderCellGroupName:
            if let room = self.room {
                var roomname = room.subject
                if roomname == nil {
                    roomname = room.roomJID?.user
                }
                
                cell.textLabel?.text = "#" + (roomname ?? "") + " (Invite Only Group)"
                if (room.isPublic) {
                    cell.textLabel?.text = "#" + (roomname ?? "") + " (Open Group)"
                }
                cell.detailTextLabel?.text = "" // Do we have creation date?
            }
            cell.accessoryView = nil
            cell.isUserInteractionEnabled = false
            cell.contentView.alpha = disabledCellAlphaValue
            cell.selectionStyle = .none
            break
        case CellIdentifier.HeaderCellAddAttachment:
            //
            break
        case CellIdentifier.HeaderCellAttachments:
            //probably open another viewController
            break
        default:
            break
        }
        return cell
    }
    
    open func didSelectHeaderCell(type:String) {
        switch type {
            case CellIdentifier.HeaderCellAddAttachment:
                addAttachmentSelected()
                break
            default: break
        }
    }
    
    func addAttachmentSelected(){
        
        //let documentPicker = UIDocumentPickerViewController(documentTypes: [String(kUTTypePDF)], in: .import)
        //let documentPicker = UIDocumentPickerViewController(documentTypes: ["com.apple.iwork.pages.pages", "com.apple.iwork.numbers.numbers", "com.apple.iwork.keynote.key","public.image", "com.apple.application", "public.item","public.data", "public.content", "public.audiovisual-content", "public.movie", "public.audiovisual-content", "public.video", "public.audio", "public.text", "public.data", "public.zip-archive", "com.pkware.zip-archive", "public.composite-content", "public.text"], in: .import)
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["com.apple.iwork.pages.pages", "com.apple.iwork.numbers.numbers", "com.apple.iwork.keynote.key","public.image", "com.apple.application", "public.item","public.data", "public.content", "public.audiovisual-content", "public.movie", "public.audiovisual-content", "public.video", "public.text", "public.data", "public.composite-content", "public.text"], in: .import)
        
            //UTI: com.adobe.pdf
            //conforms to: public.data, public.composite-content
        
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }
    
    func doUpload(attachUrl: URL, mucname: String, xmpp: XMPPManager) {
        let hud = MBProgressHUD.showAdded(to: self.view, animated: true)
        hud.label.text = "Uploading..."
        hud.mode = MBProgressHUDMode.annularDeterminate
        let hudprogress = Progress.init(totalUnitCount: 100)
        hud.progressObject = hudprogress;
        //self.startSpinner()
        
        xmpp.fileTransferManager.uploadAttachment(file: attachUrl, mucname: mucname, hudprogress: hudprogress, completion: { (_url: URL?, error: Error?) in
            DispatchQueue.main.async {
                hud.hide(animated: true)
            }
            guard _url != nil else {
                if let error = error {
                    DDLogError("Error uploading: \(error)")
                    let alert = UIAlertController(title: "Upload Error", message: "There was a problem uploading this file", preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: UIAlertActionStyle.default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                }
                return
            }
            //self.roomAttachments.append(url.absoluteString)
            //self.tableView.reloadData()
            // do query and reload data
            self.refreshList()
        })
    }
    
    func refreshList() {
        if let room = self.room {
            self.readConnection?.read { transaction in
                if let account = room.account(with: transaction) {
                    if let xmpp = OTRProtocolManager.shared.protocol(for: account) as? XMPPManager, let roomjid = room.roomJID, let myjid = xmpp.account.bareJID {
                        //let myjid = xmpp.account.bareJID
                        xmpp.fileTransferManager.getAttachments(muc: roomjid, userjid: myjid, completion: { (_pinned: XMPPPinned?, error: Error?) in
                            guard let pinned = _pinned else {
                            DDLogError("Failed to retrieve attachments: \(roomjid.bare)")
                                return
                            }
                            // reset list
                            self.pins = pinned
                            self.roomAttachments = []
                            if let links = self.pins?.pinnedURLs {
                                for pin in links {
                                    self.roomAttachments.append(pin)
                                }
                            }
                            
                            self.tableView.reloadData()
                        })
                    }
                }
            }
        }
    }
    
    func doDownload(url: URL, key: String, iv: String, tag: String, xmpp: XMPPManager) {
        /*var prefetchedData:Data
        do {
            prefetchedData = try Data(contentsOf: url)
        } catch let error {
            DDLogError("Error prefetching data: \(error)")
        }*/
        
        let hud = MBProgressHUD.showAdded(to: self.view, animated: true)
        hud.label.text = "Downloading..."
        hud.mode = MBProgressHUDMode.annularDeterminate
        let hudprogress = Progress.init(totalUnitCount: 100)
        hud.progressObject = hudprogress;
        
        xmpp.fileTransferManager.downloadAttachment(url: url, key: key, iv: iv, tag: tag, hudprogress: hudprogress, completion: { (_data: Data?, error: Error?) in
            //self.removeSpinner()
            DispatchQueue.main.async {
                hud.hide(animated: true)
                guard let data = _data else {
                    if let error = error {
                        DDLogError("Error downloading: \(error)")
                        let alert = UIAlertController(title: "Download Error", message: "There was a problem downloading this file", preferredStyle: UIAlertControllerStyle.alert)
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: UIAlertActionStyle.default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                    }
                    return
                }
                //Change this to data instead of url
                let baseurl = URL(string: "https://" + xmpp.fileTransferManager.uploadDomain)
                if let localUrl = self.tryStoreLocal(data: data, url: url) {
                    let webview = RoomAttachmentWebViewController(url: localUrl, data: nil, baseurl: baseurl!)
                    self.navigationController?.pushViewController(webview, animated: true)
                } else {
                    let webview = RoomAttachmentWebViewController(url: url, data: data, baseurl: baseurl!)
                    self.navigationController?.pushViewController(webview, animated: true)
                }
            }
        })
    }
    
    func tryStoreLocal(data: Data, url: URL) -> URL? {
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileurl = paths[0].appendingPathComponent(url.lastPathComponent)
        
        do {
            try data.write(to: fileurl, options: .atomic)//, encoding: String.Encoding.utf8)
        } catch {
            // failed to write file – bad permissions, bad filename, missing permissions, or more likely it can't be converted to the encoding
            DDLogError("Something went wrong storing data locally")
            return nil
        }
        
        return fileurl
    }
}

// MARK: - UITableViewDataSource
extension RoomAttachmentsViewController: UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if section == 0 {
            return headerRows.count
        }
        
        return roomAttachments.count //number of attachments
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            return createHeaderCell(type: headerRows[indexPath.row], at: indexPath)
        }
        
        let cell:UITableViewCell = tableView.dequeueReusableCell(withIdentifier: DynamicCellIdentifier.attachment.rawValue, for: indexPath)
        
        let url = URL(string: roomAttachments[indexPath.row])
        let filename = url?.lastPathComponent
        cell.textLabel?.text = filename
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension RoomAttachmentsViewController:UITableViewDelegate {
    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return GenericHeaderCell.cellHeight
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return GenericHeaderCell.cellHeight
    }
    
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            didSelectHeaderCell(type: headerRows[indexPath.row])
            return
        }
        
        guard let url = URL(string: roomAttachments[indexPath.row]) else { return }
        
        let keydict = self.pins?.pinnedKeys.object(forKey: roomAttachments[indexPath.row]) as! NSMutableDictionary
        // probably need error notifcation here if can't find keys
        guard let key = keydict.object(forKey: "key"), let iv = keydict.object(forKey: "iv"), let tag = keydict.object(forKey: "tag") else {
                // handle error
            return
        }
        
        if let room = self.room {
            self.readConnection?.read { transaction in
                if let account = room.account(with: transaction) {
                    if let xmpp = OTRProtocolManager.shared.protocol(for: account) as? XMPPManager {
                        self.doDownload(url: url, key: key as! String, iv: iv as! String, tag: tag as! String, xmpp: xmpp)
                    }
                }
            }
        }
        
        //let webview = RoomAttachmentWebViewController(url: url)
        //self.navigationController?.pushViewController(webview, animated: true)
    }
}

extension RoomAttachmentsViewController: UIDocumentPickerDelegate,UINavigationControllerDelegate { 
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        let attachUrl = url as URL
        
        //check if duplicate and notify user if needed
        for attached in roomAttachments {
            if let attachedurl = URL(string: attached) {
                if attachedurl.lastPathComponent == attachUrl.lastPathComponent {
                    let alert = UIAlertController(title: "Duplicate Attachment", message: "This file is already attached", preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: UIAlertActionStyle.default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                    return
                }
            }
        }
        
        if let room = self.room {
            let roomname = room.roomJID?.bare
            
            self.readConnection?.read { transaction in
                if let account = room.account(with: transaction), roomname != nil {
                    if let xmpp = OTRProtocolManager.shared.protocol(for: account) as? XMPPManager {
                        self.doUpload(attachUrl: attachUrl, mucname: roomname!, xmpp: xmpp)
                    } 
                }
            }
        }
    }
    
    private func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("view was cancelled")
        dismiss(animated: true, completion: nil)
    }
}
