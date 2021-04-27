//
//  CoreDetailsViewController.swift
//  Created by Andy Friedman on 1/28/20.
//  Copyright © 2020 Glacier Security. All rights reserved.

import UIKit
import NetworkExtension
import SystemConfiguration.CaptiveNetwork

open class CoreDetailsViewController: UITableViewController {
    let targetManager = NEVPNManager.shared()
    
    var hidden = false
    var ssids = [String]()
    var selectedRow = 0
    var vSpinner : UIView?
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Core Connection Details"
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "wificell")
        
        getSSIDStatus()
        
        if ssids.count > 0 {
            hidden = false
            selectedRow = 1
        } else {
            hidden = true
            selectedRow = 0
        }
    }
    
    override open func viewWillDisappear(_ animated: Bool) {
        self.stopSpinner()
        super.viewWillDisappear(animated)
    }
    
    private func startSpinner() {
        self.showSpinner(onView: self.view)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.stopSpinner()
        }
    }
    
    private func stopSpinner() {
        self.removeSpinner()
    }
    
    private func getSSIDStatus() {
        ssids.removeAll()
        if let rules = targetManager.onDemandRules {
            for rule in rules {
                if let matches = rule.ssidMatch {
                    for match in matches {
                        ssids.append(match)
                    }
                }
            }
        }
    }
    
    @IBAction func addSSIDException(_ sender: Any) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = NSTextAlignment.left
        
        // get current SSID
        var ssidholder = "Wifi network"
        if let curssid = retrieveCurrentSSID() {
            ssidholder = curssid
        }
        
        let addmsg = "\nThis will turn off Core Connect when connected through this Wifi network, and turn it back on outside of this Wifi network."
        
        let alert = UIAlertController(title: NSLocalizedString("Trust Network", comment: "Wifi to trust"), message: addmsg, preferredStyle: UIAlertControllerStyle.alert)
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: UIAlertActionStyle.default, handler: nil))
        
        if ssids.count >= 5 {
            let badmsg = "\nYou may only have up to 5 trusted networks. Please remove networks if you'd like to add new ones."
            let messageText = NSMutableAttributedString(
                string: badmsg,
                attributes: [
                    NSAttributedStringKey.paragraphStyle: paragraphStyle,
                    NSAttributedStringKey.font: UIFont.systemFont(ofSize: 13)
                ]
            )
            alert.setValue(messageText, forKey: "attributedMessage")
        } else {
            let messageText = NSMutableAttributedString(
                string: addmsg,
                attributes: [
                    NSAttributedStringKey.paragraphStyle: paragraphStyle,
                    NSAttributedStringKey.font: UIFont.systemFont(ofSize: 13)
                ]
            )
            
            alert.setValue(messageText, forKey: "attributedMessage")
            alert.addAction(UIAlertAction(title: NSLocalizedString("Trust Network", comment: "Trust Network button"), style: UIAlertActionStyle.default, handler: {(action: UIAlertAction!) in
                let firstTextField = alert.textFields![0] as UITextField
                var ssid = firstTextField.placeholder
                if ((firstTextField.text?.count)! > 1) {
                    ssid = firstTextField.text
                }
                if (!self.ssids.contains(ssid!)) {
                    self.startSpinner()
                    VPNManager.shared.addSSID(ssid!)
                    self.ssids.append(ssid!)
                    self.tableView.reloadData()
                }
            }))
            alert.addTextField(configurationHandler: {(textField: UITextField!) in
                textField.placeholder = ssidholder
                textField.isSecureTextEntry = false
            })
        }
        
        self.present(alert, animated: true, completion: nil)
    }
    
    /// retrieve the current SSID from a connected Wifi network
    private func retrieveCurrentSSID() -> String? {
        let interfaces = CNCopySupportedInterfaces() as? [String]
        let interface = interfaces?
            .compactMap { [weak self] in self?.retrieveInterfaceInfo(from: $0) }
            .first

        return interface
    }

    /// Retrieve information about a specific network interface
    private func retrieveInterfaceInfo(from interface: String) -> String? {
        guard let interfaceInfo = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: AnyObject],
            let ssid = interfaceInfo[kCNNetworkInfoKeySSID as String] as? String
            else {
                return nil
        }
        return ssid
    }
    
    override open func numberOfSections(in tableView: UITableView) -> Int
    {
        if hidden {
            return 1
        }
        return 3
    }
    
    override open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 1 {
            if hidden {
                return 0
            } else if (self.ssids.count == 0) {
                return 1
            } else {
                return self.ssids.count
            }
        } else if section == 2 {
            if hidden {
                return 0
            }
        }
        return super.tableView(tableView, numberOfRowsInSection: section)
    }
    
    override open func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return super.tableView(tableView, heightForHeaderInSection: section)
    }

    override open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 {
            
            let cell = tableView.dequeueReusableCell(withIdentifier: "wificell")!
            if (self.ssids.count == 0) {
                cell.textLabel?.text = "No SSIDs"
            } else {
                cell.textLabel?.text = ssids[indexPath.row]
            }
            return cell
        }
        return super.tableView(tableView, cellForRowAt: indexPath)
    }

    override open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            
            if (indexPath.row == selectedRow) {
                return
            }
            
            selectedRow = indexPath.row
            
            if selectedRow == 0 {
                //hidden = true
                handleHideSelection(indexPath)
            } else {
                hidden = false
                for cell in tableView.visibleCells {
                    cell.accessoryType = .none
                }
                tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
                tableView.reloadData()
            }
        }
    }
    
    private func handleHideSelection(_ indexPath: IndexPath) {
        if (self.ssids.count == 0) {
            self.hidden = true
            for cell in self.tableView.visibleCells {
                cell.accessoryType = .none
            }
            self.tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
            self.tableView.reloadData()
            return
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = NSTextAlignment.left
        
        let addmsg = "\nThis will remove trusted networks so that Core will run on all Wifi networks. Are you sure you want to do this?"
        
        let alert = UIAlertController(title: NSLocalizedString("Remove Trusted Networks", comment: "Remove trusted networks"), message: addmsg, preferredStyle: UIAlertControllerStyle.alert)
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: UIAlertActionStyle.default, handler: nil))
        
        let messageText = NSMutableAttributedString(
            string: addmsg,
            attributes: [
                NSAttributedStringKey.paragraphStyle: paragraphStyle,
                NSAttributedStringKey.font: UIFont.systemFont(ofSize: 13)
            ]
        )
            
        alert.setValue(messageText, forKey: "attributedMessage")
        alert.addAction(UIAlertAction(title: NSLocalizedString("Remove", comment: "Remove Networks button"), style: UIAlertActionStyle.default, handler: {(action: UIAlertAction!) in
            self.hidden = true
            
            for cell in self.tableView.visibleCells {
                cell.accessoryType = .none
            }
            self.tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
            
            self.startSpinner()
            VPNManager.shared.removeSSIDs()
            self.ssids.removeAll()
            
            self.tableView.reloadData()
        }))
        
        self.present(alert, animated: true, completion: nil)
    }

    override open func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            cell.accessoryType = indexPath.row == selectedRow ? .checkmark : .none
        }
    }
    
    override open func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if indexPath.section == 1 {
            if (editingStyle == UITableViewCell.EditingStyle.delete) {
                self.startSpinner()
                let remove = self.ssids[indexPath.row]
                self.ssids.remove(at: indexPath.row)
                VPNManager.shared.removeSSID(remove)
            }
            tableView.reloadData()
        }
    }
}

extension CoreDetailsViewController {
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
