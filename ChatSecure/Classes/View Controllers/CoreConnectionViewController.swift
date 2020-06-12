//
//  CoreConnectionViewController.swift
//  Created by Andy Friedman on 10/25/19.
//  Copyright © 2019 Glacier Security. All rights reserved.

import UIKit
import NetworkExtension

@objc public protocol CoreConnectionDelegate: NSObjectProtocol {
    func coreSettingChanged()
}

@objc open class CoreConnectionViewController: UIViewController, UITextViewDelegate, CoreConnectionDelegate {

    var settingsManager: OTRSettingsManager?
    var coreSetting: OTRBoolSetting?
    
    @IBOutlet weak var coreConnectionLabel: UILabel!
    @IBOutlet weak var coreConnectionSwitch: UISwitch!
    @IBOutlet weak var lockLabel: UILabel!
    @IBOutlet weak var coreDescriptionTextView: UITextView!
    
    var vSpinner : UIView?
    var coreOptionsContoller: CoreOptionsViewController?
    
    let targetManager = NEVPNManager.shared()
    
    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange, object: self.targetManager.connection, queue: OperationQueue.main, using: { notification in
            self.coreConnectionSwitch.isOn = (self.targetManager.isEnabled && self.targetManager.connection.status != .disconnected && self.targetManager.connection.status != .disconnecting && self.targetManager.connection.status != .invalid)
        })
    }
    
    override open func viewWillDisappear(_ animated: Bool) {
        self.stopSpinner()
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }
    
    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Core"
        
        let coreDescription = "Enabling Core Connect adds an additional layer of encryption and anonymitity to all data exiting your device.\n\nWhen enabling Core Connect for the first time, Glacier will request permission to install a profile. This permission enables Glacier to protect your identity & corporate data.\n\nGlacier doesn't allow your admin to see browsing history.\n\nLearn more how Glacier protects you."
        
        let attributedString = NSMutableAttributedString(string: coreDescription)
        attributedString.addAttribute(.link, value: "https://www.glaciersecurity.com/ios-core", range: NSRange(location: 370, length: 12))
        let textRange = NSMakeRange(0, coreDescription.count)
        attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 14), range: textRange)
        
        if #available(iOS 13.0, *) {
            let tcolor = UIColor.label
            attributedString.addAttribute(.foregroundColor, value: tcolor, range: textRange)
        }
        
        coreDescriptionTextView.attributedText = attributedString
        coreDescriptionTextView.delegate = self
        
        VPNManager.shared.setVPNView(self)
        
        self.setCoreSetting()
    }
    
    override open func prepare(for segue: UIStoryboardSegue, sender: Any?) {
            
            switch segue.destination {
                
            case let coreController as CoreOptionsViewController:
                coreOptionsContoller = coreController
                coreOptionsContoller?.setCoreConnectionDelegate(delegate: self)
                
            default:
                break
            }
    }
    
    public func coreSettingChanged() {
        self.startSpinner()
    }
    
    @available(iOS 10.0, *)
    @available(iOSApplicationExtension, unavailable)
    private func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        Application.shared.open(URL)
        return false
    }
    
    @objc open func addSettings(_ settingsMgr: OTRSettingsManager) {
        self.settingsManager = settingsMgr
    }
    
    func setCoreSetting() {
        if let coreOTRSetting = self.settingsManager?.setting(forOTRSettingKey: kGlacierCoreConnection), let coreSetting = coreOTRSetting as? OTRBoolSetting {
            self.coreConnectionLabel.text = coreOTRSetting.title;
            coreConnectionSwitch.setOn(VPNManager.shared.vpnIsActive(), animated: false)
            coreConnectionSwitch.addTarget(coreSetting, action: #selector(coreSetting.toggle), for: UIControl.Event.valueChanged)
        }
        
        coreConnectionSwitch.addTarget(self, action: #selector(switchChanged), for: UIControl.Event.valueChanged)
    }
    
    @objc open func setCoreOn(_ turnon: Bool) {
        coreConnectionSwitch.setOn(turnon, animated: true)
    }
    
    @objc func switchChanged(coreSwitch: UISwitch) {
        let value = coreSwitch.isOn
        if (value) {
            VPNManager.shared.turnOnVpn()
        } else {
            VPNManager.shared.turnOffVpn()
        }
        self.startSpinner()
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
}

extension CoreConnectionViewController {
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
