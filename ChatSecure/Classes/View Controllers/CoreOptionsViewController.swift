//
//  CoreDetailsViewController.swift
//  Created by Andy Friedman on 1/28/20.
//  Copyright © 2020 Glacier Security. All rights reserved.

import UIKit
import NetworkExtension

open class CoreOptionsViewController: UITableViewController {
    let targetManager = NEVPNManager.shared()

    @IBOutlet weak var cellularSwitch: UISwitch!
    @IBOutlet weak var wifiSwitch: UISwitch!
    @IBOutlet weak var wifiNetworksCountLabel: UILabel!
    
    var hidden = false
    var wifihidden = false
    var ssids = [String]()
    
    var coreDelegate: CoreConnectionDelegate?
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        //set slider values based on target manager also
        cellularSwitch.addTarget(self, action: #selector(cellularSwitchChanged), for: UIControl.Event.valueChanged)
        wifiSwitch.addTarget(self, action: #selector(wifiSwitchChanged), for: UIControl.Event.valueChanged)
        
        hidden = VPNManager.shared.vpnIsDisabled()
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(coreUpdate), name: NSNotification.Name.NEVPNStatusDidChange, object: nil)
        
        setSwitchStatus()
    }
    
    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }
    
    public func setCoreConnectionDelegate(delegate: CoreConnectionDelegate) {
        self.coreDelegate = delegate
    }
    
    @objc private func coreUpdate(_ sender: Any?) {
        hidden = VPNManager.shared.vpnIsDisabled()
        if (!hidden) {
            setSwitchStatus()
        }
        tableView.reloadData()
    }
    
    private func setSwitchStatus() {
        ssids.removeAll()
        var wifiFound = false
        var cellularFound = false
        if let rules = targetManager.onDemandRules {
            for rule in rules {
                if let matches = rule.ssidMatch {
                    for match in matches {
                        ssids.append(match)
                    }
                }
                if (rule is NEOnDemandRuleConnect && rule.interfaceTypeMatch == NEOnDemandRuleInterfaceType.wiFi) {
                    wifiFound = true
                }
                if (rule is NEOnDemandRuleConnect && rule.interfaceTypeMatch == NEOnDemandRuleInterfaceType.cellular) {
                    cellularFound = true
                }
            }
        }
        
        if wifiFound {
            wifiSwitch.isOn = true
            wifihidden = false
        } else {
            wifiSwitch.isOn = false
            wifihidden = true
        }
        
        if cellularFound {
            cellularSwitch.isOn = true
        } else {
            cellularSwitch.isOn = false
        }
        
        if (ssids.count == 0) {
            wifiNetworksCountLabel.text = "All"
        } else if (ssids.count == 1) {
            wifiNetworksCountLabel.text = "\(ssids.count) network trusted"
        } else {
            wifiNetworksCountLabel.text = "\(ssids.count) networks trusted"
        }
    }
    
    override open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if hidden {
            return 0
        } else if wifihidden {
            return 2
        }
       return super.tableView(tableView, numberOfRowsInSection: section)
    }
    
    override open func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if hidden {
            return CGFloat.leastNonzeroMagnitude
        }
        return super.tableView(tableView, heightForHeaderInSection: section)
    }
    
    @objc func cellularSwitchChanged(coreSwitch: UISwitch) {
        let value = cellularSwitch.isOn
        if (value) {
            VPNManager.shared.turnOnCellular()
        } else {
            VPNManager.shared.turnOffCellular()
        }
        
        self.coreDelegate?.coreSettingChanged()
    }
    
    @objc func wifiSwitchChanged(coreSwitch: UISwitch) {
        let value = wifiSwitch.isOn
        if (value) {
            VPNManager.shared.turnOnWifi()
            wifihidden = false
        } else {
            VPNManager.shared.turnOffWifi()
            wifihidden = true
        }
        self.coreDelegate?.coreSettingChanged()
        tableView.reloadData()
    }
}
