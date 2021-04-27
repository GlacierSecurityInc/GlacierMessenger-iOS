//
//  OMEMODeviceFingerprintCell.swift
//  ChatSecure
//
//  Created by Chris Ballinger on 10/14/16.
//  Copyright © 2016 Chris Ballinger. All rights reserved.
//

import UIKit
import XLForm
import XMPPFramework
import FormatterKit
import OTRKit

private extension String {
    //http://stackoverflow.com/a/34454633/805882
    func splitEvery(_ n: Int) -> [String] {
        var result: [String] = []
        let chars = Array(self)
        for index in stride(from: 0, to: chars.count, by: n) {
            result.append(String(chars[index..<min(index+n, chars.count)]))
        }
        return result
    }
}

public extension NSData {
    /// hex, split every 8 bytes by a space
    @objc func humanReadableFingerprint() -> String {
        return (self as NSData).xmpp_hexStringValue.splitEvery(8).joined(separator: " ")
    }
}

public extension XLFormBaseCell {
    
    @objc class func defaultRowDescriptorType() -> String {
        let type = NSStringFromClass(self)
        return type
    }
    
    @objc class func registerCellClass(_ forType: String) {
        let bundle = GlacierInfo.resourcesBundle
        let path = bundle.bundlePath
        guard let bundleName = (path as NSString?)?.lastPathComponent else {
            return
        }
        let className = bundleName + "/" + NSStringFromClass(self)
        XLFormViewController.cellClassesForRowDescriptorTypes().setObject(className, forKey: forType as NSString)
    }
}

@objc(OMEMODeviceFingerprintCell)
open class OMEMODeviceFingerprintCell: UITableViewCell { //XLFormBaseCell {
    
    @IBOutlet weak var fingerprintLabel: UILabel!
    @IBOutlet weak var trustSwitch: UISwitch!
    @IBOutlet weak var lastSeenLabel: UILabel!
    @IBOutlet weak var trustLevelLabel: UILabel!
    private var omemoDevice:OMEMODevice?
    
    @objc @IBOutlet weak var fingerprintWidth: NSLayoutConstraint!
    
    fileprivate static let intervalFormatter = TTTTimeIntervalFormatter()
    
    @objc public class func cellIdentifier() -> String {
        return "OMEMODeviceFingerprintCell"
    }
    
    @objc public func updateWithDevice(_ device:OMEMODevice) {
        updateCellFromDevice(device)
    }
    
    @IBAction func switchValueChanged(_ sender: UISwitch) {
        if let device = omemoDevice {
            switchValueWithDevice(device)
        }
    }
    
    fileprivate func updateCellFromDevice(_ device: OMEMODevice) {
        omemoDevice = device
        let trusted = device.isTrusted()
        trustSwitch.isOn = trusted
        trustSwitch.isEnabled = true
        
        // we've already filtered out devices w/o public keys
        // so publicIdentityKeyData should never be nil
        let fingerprint = device.humanReadableFingerprint
        
        fingerprintLabel.text = fingerprint
        let interval = -Date().timeIntervalSince(device.lastSeenDate)
        let since = type(of: self).intervalFormatter.string(forTimeInterval: interval)
        let lastSeen = "Session established: " + since!  //Instead of OMEMO
        lastSeenLabel.text = lastSeen
        if (device.trustLevel == .trustedTofu) {
            trustLevelLabel.text = "Trusted"//"TOFU"
        } else if (device.trustLevel == .trustedUser) {
            trustLevelLabel.text = "Trusted"//VERIFIED_STRING()
        } else if (device.trustLevel == .removed) {
            trustLevelLabel.text = Removed_By_Server()
        } else {
            trustLevelLabel.text = UNTRUSTED_DEVICE_STRING()
        }
    }
    
    fileprivate func switchValueWithDevice(_ device: OMEMODevice) {
        if (trustSwitch.isOn) {
            device.trustLevel = .trustedUser
            if (device.isExpired()){
                device.lastSeenDate = Date()
            }
        } else {
            device.trustLevel = .untrusted
        }
        omemoDevice = device
        updateCellFromDevice(device)
        
        let deviceCopy = device.copy() as! OMEMODevice
        deviceCopy.trustLevel = device.trustLevel
        if (deviceCopy.trustLevel == .trustedUser && device.isExpired()) {
            deviceCopy.lastSeenDate = device.lastSeenDate
        }
        OTRDatabaseManager.sharedInstance().writeConnection?.asyncReadWrite({ (t: YapDatabaseReadWriteTransaction) in
            deviceCopy.save(with: t)
        })
    }
    
    fileprivate func updateCellFromFingerprint(_ fingerprint: OTRFingerprint) {
        fingerprintLabel.text = (fingerprint.fingerprint as NSData).humanReadableFingerprint()
        lastSeenLabel.text = "OTR"
        if (fingerprint.trustLevel == .trustedUser ||
            fingerprint.trustLevel == .trustedTofu) {
            trustSwitch.isOn = true
        } else {
            trustSwitch.isOn = false
        }
        if (fingerprint.trustLevel == .trustedTofu) {
            trustLevelLabel.text = "TOFU"
        } else if (fingerprint.trustLevel == .trustedUser) {
            trustLevelLabel.text = VERIFIED_STRING()
        } else {
            trustLevelLabel.text = UNTRUSTED_DEVICE_STRING()
        }
    }
    
}
