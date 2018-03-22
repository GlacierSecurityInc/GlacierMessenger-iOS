//
//  AccountDetailViewController.swift
//  ChatSecure
//
//  Created by Chris Ballinger on 3/5/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

import UIKit
import OTRAssets
import PureLayout

struct DetailCellInfo {
    enum ActionType {
        case editAccount
        case manageKeys
        case serverInfo
    }
    let title: String
    let type: ActionType
    let action: (_ tableView: UITableView, _ indexPath: IndexPath, _ sender: Any) -> (Void)
}

enum TableSections: Int {
    case account
    case changedisplay
    case delete
    static let allValues = [account, changedisplay, delete]
}

enum AccountRows: Int {
    case account
    static let allValues = [account]
}

@objc(OTRAccountDetailViewController)
open class AccountDetailViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    public let tableView: UITableView
    public var account: OTRXMPPAccount
    let longLivedReadConnection: YapDatabaseConnection
    let writeConnection: YapDatabaseConnection
    var detailCells: [DetailCellInfo] = []
    let DetailCellIdentifier = "DetailCellIdentifier"
    
    let xmpp: OTRXMPPManager
    
    @objc public init(account: OTRXMPPAccount, xmpp: OTRXMPPManager, longLivedReadConnection: YapDatabaseConnection, writeConnection: YapDatabaseConnection) {
        self.account = account
        self.longLivedReadConnection = longLivedReadConnection
        self.writeConnection = writeConnection
        self.xmpp = xmpp
        self.tableView = UITableView(frame: CGRect.zero, style: .grouped)
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        self.title = ACCOUNT_STRING()
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonPressed(_:)))
        navigationItem.rightBarButtonItem = doneButton
        setupTableView()
        setupDetailCells()
    }
    
    private func setupTableView() {
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.autoPinEdgesToSuperviewEdges()
        let bundle = OTRAssets.resourcesBundle
        for identifier in [XMPPAccountCell.cellIdentifier(), SingleButtonTableViewCell.cellIdentifier()] {
            let nib = UINib(nibName: identifier, bundle: bundle)
            tableView.register(nib, forCellReuseIdentifier: identifier)
        }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: DetailCellIdentifier)
    }
    
    private func setupDetailCells() {
        detailCells = [
            DetailCellInfo(title: EDIT_ACCOUNT_STRING(), type: .editAccount, action: { [weak self] (_, _, sender) -> (Void) in
                guard let strongSelf = self else { return }
                strongSelf.pushLoginView(account: strongSelf.account, sender: sender)
            }),
            DetailCellInfo(title: MANAGE_MY_KEYS(), type: .manageKeys, action: { [weak self] (_, _, sender) -> (Void) in
                guard let strongSelf = self else { return }
                strongSelf.pushKeyManagementView(account: strongSelf.account, sender: sender)
            }),
            DetailCellInfo(title: SERVER_INFORMATION_STRING(), type: .serverInfo, action: { [weak self] (_, _, sender) -> (Void) in
                guard let strongSelf = self else { return }
                strongSelf.pushServerInfoView(account: strongSelf.account, sender: sender)
            })
        ]
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(loginStatusChanged(_:)), name: NSNotification.Name(rawValue: OTRXMPPLoginStatusNotificationName), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(serverCheckUpdate(_:)), name: ServerCheck.UpdateNotificationName, object: xmpp.serverCheck)
        tableView.reloadData()
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notifications
    
    @objc func serverCheckUpdate(_ notification: Notification) {
        setupDetailCells() // refresh server info warning label
        tableView.reloadData()
    }
    
    @objc func loginStatusChanged(_ notification: Notification) {
        tableView.reloadData()
        // Show certificate warnings
        if let lastError = xmpp.lastConnectionError,
            let certWarning = UIAlertController.certificateWarningAlert(error: lastError, saveHandler: { action in
                self.attemptLogin(action)
            }) {
            present(certWarning, animated: true, completion: nil)
        }
    }
    
    // MARK: - User Actions
    
    func showMigrateAccount(account: OTRXMPPAccount, sender: Any) {
        let migrateVC = OTRAccountMigrationViewController(oldAccount: account)
        self.navigationController?.pushViewController(migrateVC, animated: true)
    }
    
    func showDeleteDialog(account: OTRXMPPAccount, sender: Any) {
        let alert = UIAlertController(title: "\(DELETE_ACCOUNT_MESSAGE_STRING()) account?", message: nil, preferredStyle: .actionSheet)
        let cancel = UIAlertAction(title: CANCEL_STRING(), style: .cancel)
        let delete = UIAlertAction(title: DELETE_ACCOUNT_BUTTON_STRING(), style: .destructive) { (action) in
            let protocols = OTRProtocolManager.sharedInstance()
            if let xmpp = protocols.protocol(for: account) as? OTRXMPPManager,
                xmpp.connectionStatus != .disconnected {
                xmpp.disconnect()
            }
            protocols.removeProtocol(for: account)
            OTRAccountsManager.remove(account)
            self.dismiss(animated: true, completion: nil)
        }
        alert.addAction(cancel)
        alert.addAction(delete)
        if let sourceView = sender as? UIView {
            alert.popoverPresentationController?.sourceView = sourceView;
            alert.popoverPresentationController?.sourceRect = sourceView.bounds;
        }
        present(alert, animated: true, completion: nil)
    }
    
    func showChangeDisplayNameDialog(account: OTRXMPPAccount, sender: Any) {
        let alert = UIAlertController(title: "Change Display Name", message: nil, preferredStyle: .alert)
        alert.addTextField { (textField : UITextField!) -> Void in
            textField.placeholder = "Display Name"
        }
        //alertController.addTextField(configurationHandler: {(textField : UITextField!) -> Void in
        
        let cancel = UIAlertAction(title: CANCEL_STRING(), style: .cancel)
        let change = UIAlertAction(title: "Change", style: .default) { (action) in
            if let newname = alert.textFields?.first?.text {
                if newname != account.displayName {
                    self.handleUpdatedDisplayName(newName: newname, account: account)
                }
            }
            self.dismiss(animated: true, completion: nil)
        }
        alert.addAction(cancel)
        alert.addAction(change)
        
        if let sourceView = sender as? UIView {
            alert.popoverPresentationController?.sourceView = sourceView;
            alert.popoverPresentationController?.sourceRect = sourceView.bounds;
        }
        present(alert, animated: true, completion: nil)
    }
    
    func handleUpdatedDisplayName(newName: String, account: OTRXMPPAccount) {
        if (account.vCardTemp == nil) {
            account.vCardTemp = XMPPvCardTemp.v()
        }
    
        account.vCardTemp.nickname = newName
        let protocols = OTRProtocolManager.sharedInstance()
        if let xmpp = protocols.protocol(for: account) as? OTRXMPPManager {
            xmpp.updateNickname(account.vCardTemp)
            xmpp.forcevCardUpdate(completion: {_ in })
        }
    }
    
    func showLogoutDialog(account: OTRXMPPAccount, sender: Any) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let cancel = UIAlertAction(title: CANCEL_STRING(), style: .cancel)
        let logout = UIAlertAction(title: LOGOUT_STRING(), style: .destructive) { (action) in
            let protocols = OTRProtocolManager.sharedInstance()
            if let xmpp = protocols.protocol(for: account) as? OTRXMPPManager,
                xmpp.connectionStatus != .disconnected {
                xmpp.disconnect()
            }
        }
        alert.addAction(cancel)
        alert.addAction(logout)
        if let sourceView = sender as? UIView {
            alert.popoverPresentationController?.sourceView = sourceView;
            alert.popoverPresentationController?.sourceRect = sourceView.bounds;
        }
        present(alert, animated: true, completion: nil)
    }
    
    func showInviteFriends(account: OTRXMPPAccount, sender: Any) {
        ShareController.shareAccount(account, sender: sender, viewController: self)
    }
    
    func pushLoginView(account: OTRXMPPAccount, sender: Any) {
        let login = OTRBaseLoginViewController(account: account)
        navigationController?.pushViewController(login, animated: true)
    }
    
    func pushKeyManagementView(account: OTRXMPPAccount, sender: Any) {
        let form = UserProfileViewController.profileFormDescriptorForAccount(account, buddies: [], connection: writeConnection)
        let keys = UserProfileViewController(accountKey: account.uniqueId, connection: writeConnection, form: form)
        navigationController?.pushViewController(keys, animated: true)
    }
    
    func pushServerInfoView(account: OTRXMPPAccount, sender: Any) {
        let scvc = ServerCapabilitiesViewController(serverCheck: xmpp.serverCheck)
        navigationController?.pushViewController(scvc, animated: true)
    }
    
    @objc private func doneButtonPressed(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
    
    private func attemptLogin(_ sender: Any) {
        let protocols = OTRProtocolManager.sharedInstance()
        if let _ = self.account.password,
            self.account.accountType != .xmppTor {
            protocols.loginAccount(self.account)
        } else {
            self.pushLoginView(account: self.account, sender: sender)
        }
    }

    // MARK: - Table view data source & delegate

    open func numberOfSections(in tableView: UITableView) -> Int {
        return TableSections.allValues.count
    }

    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let tableSection = TableSections(rawValue: section) else {
            return 0
        }
        switch tableSection {
        case .account:
            return AccountRows.allValues.count
        case .changedisplay, .delete:
            return 1
        }
    }

    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = TableSections(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        switch section {
        case .account:
            if let row = AccountRows(rawValue: indexPath.row) {
                switch row {
                case .account:
                    return accountCell(account: account, tableView: tableView, indexPath: indexPath)
                }
            }
        case .changedisplay:
            return changeDisplayNameCell(account: account, tableView: tableView, indexPath: indexPath)
        case .delete:
            return deleteCell(account: account, tableView: tableView, indexPath: indexPath)
        }
        return UITableViewCell() // this should never be reached
    }
    
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = TableSections(rawValue: indexPath.section) else {
            return
        }
        switch section {
        case .account:
            if let row = AccountRows(rawValue: indexPath.row) {
                switch row {
                case .account:
                    break
                }
            }
        case .changedisplay, .delete:
            self.tableView.deselectRow(at: indexPath, animated: true)
            if let cell = self.tableView(tableView, cellForRowAt: indexPath) as? SingleButtonTableViewCell, let action = cell.buttonAction {
                action(cell, cell.button)
            }
            break
        }
    }
    
    open func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        var height = UITableViewAutomaticDimension
        guard let section = TableSections(rawValue: indexPath.section) else {
            return height
        }
        switch section {
        case .account:
            if let row = AccountRows(rawValue: indexPath.row) {
                switch row {
                case .account:
                    height = XMPPAccountCell.cellHeight()
                    break
                }
            }
        case .changedisplay, .delete:
            break
        }
        return height
    }
    
    // MARK: - Cells
    
    func accountCell(account: OTRXMPPAccount, tableView: UITableView, indexPath: IndexPath) -> XMPPAccountCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: XMPPAccountCell.cellIdentifier(), for: indexPath) as? XMPPAccountCell else {
            return XMPPAccountCell()
        }
        cell.setAppearance(account: account)
        cell.infoButton.isHidden = true
        cell.selectionStyle = .none
        
        // tap 5 times to get to app based login view
        let gestureSwift2AndHigher = UITapGestureRecognizer(target: self, action:  #selector (self.editAction (_:)))
        gestureSwift2AndHigher.numberOfTapsRequired = 5
        cell.addGestureRecognizer(gestureSwift2AndHigher)
        
        return cell
    }
    
    @objc func editAction(_ sender:UITapGestureRecognizer){
        self.pushLoginView(account: self.account, sender: sender)
    }
    
    func loginLogoutCell(account: OTRXMPPAccount, tableView: UITableView, indexPath: IndexPath) -> SingleButtonTableViewCell {
        let cell = singleButtonCell(account: account, tableView: tableView, indexPath: indexPath)
        
        switch xmpp.connectionStatus {
        case .connecting:
            cell.button.setTitle("\(CONNECTING_STRING())...", for: .normal)
            cell.button.isEnabled = false
        case .disconnecting,
             .disconnected:
            cell.button.setTitle(LOGIN_STRING(), for: .normal)
            cell.buttonAction = { [weak self] (cell, sender) in
                guard let strongSelf = self else { return }
                strongSelf.attemptLogin(sender)
            }
            break
        case .connected:
            cell.button.setTitle(LOGOUT_STRING(), for: .normal)
            cell.buttonAction = { [weak self] (cell, sender) in
                guard let strongSelf = self else { return }
                strongSelf.showLogoutDialog(account: strongSelf.account, sender: sender)
            }
            cell.button.setTitleColor(UIColor.red, for: .normal)
            break
        }
        return cell
    }
    
    func detailCell(account: OTRXMPPAccount, tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let detail = detailCells[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: DetailCellIdentifier, for: indexPath)
        var title = detail.title
        switch  detail.type {
        case .editAccount:
            let editAccountText = EDIT_ACCOUNT_STRING()
            if xmpp.lastConnectionError != nil {
                title = "\(editAccountText)  ❌"
            }
        case .serverInfo:
            let serverInfoText = SERVER_INFORMATION_STRING()
            if xmpp.serverCheck.getCombinedPushStatus() == .broken &&
                OTRBranding.shouldShowPushWarning {
                title = "\(serverInfoText)  ⚠️"
            }
        default:
            break
        }
        
        cell.textLabel?.text = title
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    public func singleButtonCell(account: OTRXMPPAccount, tableView: UITableView, indexPath: IndexPath) -> SingleButtonTableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: SingleButtonTableViewCell.cellIdentifier(), for: indexPath) as? SingleButtonTableViewCell else {
            return SingleButtonTableViewCell()
        }
        cell.button.setTitleColor(nil, for: .normal)
        cell.selectionStyle = .default
        cell.button.isEnabled = true
        return cell
    }
    
    func migrateCell(account: OTRXMPPAccount, tableView: UITableView, indexPath: IndexPath) -> SingleButtonTableViewCell {
        let cell = singleButtonCell(account: account, tableView: tableView, indexPath: indexPath)
        cell.button.setTitle(MIGRATE_ACCOUNT_STRING(), for: .normal)
        cell.buttonAction = { [weak self] (cell, sender) in
            guard let strongSelf = self else { return }
            strongSelf.showMigrateAccount(account: strongSelf.account, sender: sender)
        }
        return cell
    }
    
    func inviteCell(account: OTRXMPPAccount, tableView: UITableView, indexPath: IndexPath) -> SingleButtonTableViewCell {
        let cell = singleButtonCell(account: account, tableView: tableView, indexPath: indexPath)
        cell.button.setTitle(INVITE_FRIENDS_STRING(), for: .normal)
        cell.buttonAction = { [weak self] (cell, sender) in
            guard let strongSelf = self else { return }
            strongSelf.showInviteFriends(account: strongSelf.account, sender: sender)
        }
        return cell
    }
    
    func deleteCell(account: OTRXMPPAccount, tableView: UITableView, indexPath: IndexPath) -> SingleButtonTableViewCell {
        let cell = singleButtonCell(account: account, tableView: tableView, indexPath: indexPath)
        cell.button.setTitle(DELETE_ACCOUNT_BUTTON_STRING(), for: .normal)
        cell.buttonAction = { [weak self] (cell, sender) in
            guard let strongSelf = self else { return }
            strongSelf.showDeleteDialog(account: strongSelf.account, sender: sender)
        }
        cell.button.setTitleColor(UIColor.red, for: .normal)
        return cell
    }
    
    func changeDisplayNameCell(account: OTRXMPPAccount, tableView: UITableView, indexPath: IndexPath) -> SingleButtonTableViewCell {
        let cell = singleButtonCell(account: account, tableView: tableView, indexPath: indexPath)
        cell.button.setTitle("Change Display Name", for: .normal)
        cell.buttonAction = { [weak self] (cell, sender) in
            guard let strongSelf = self else { return }
            strongSelf.showChangeDisplayNameDialog(account: strongSelf.account, sender: sender)
        }
        //cell.button.setTitleColor(UIColor.red, for: .normal)
        return cell
    }

}
