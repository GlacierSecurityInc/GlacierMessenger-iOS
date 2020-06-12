//
//  UIAlertController+ChatSecure.swift
//  ChatSecureCore
//
//  Created by Chris Ballinger on 8/1/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

import UIKit
import OTRAssets

public extension UIAlertController {
    
    /** Returns a cert-pinning alert if needed */
    @objc static func certificateWarningAlert(error: Error, saveHandler: @escaping (_ action: UIAlertAction) -> Void) -> UIAlertController? {
        let nsError = error as NSError
        guard let errorCode = OTRXMPPErrorCode(rawValue: nsError.code),
            errorCode == .sslError,
            let certData = nsError.userInfo[OTRXMPPSSLCertificateDataKey] as? Data,
            let hostname = nsError.userInfo[OTRXMPPSSLHostnameKey] as? String,
            let trustResultTypeValue = nsError.userInfo[OTRXMPPSSLTrustResultKey] as? UInt32,
            let trustResultType = SecTrustResultType(rawValue: trustResultTypeValue) else {
            return nil
        }
        
        let fingerprint = OTRCertificatePinning.sha256Fingerprint(forCertificateData: certData)
        var message = "\(hostname)\n\nSHA256\n\(fingerprint)"
        
        let certAlert = UIAlertController(title: NEW_CERTIFICATE_STRING(), message: nil, preferredStyle: .alert)
        
        var glacierpublic = false
        if (hostname.contains(OTRSecrets.defaultPublicHost()) || hostname.contains(OTRSecrets.altPublicHost())) {
            certAlert.title = "Client Updated"
            message = "\n\nHeads up! Glacier has been updated. Tap Save to continue."
            glacierpublic = true
        }
        
        // Bail out if we can't find public key
        guard OTRCertificatePinning.publicKey(withCertData: certData) != nil else {
            certAlert.message = "\(message)\n\nX \(PUBLIC_KEY_ERROR_STRING())"
            let ok = UIAlertAction(title: OK_STRING(), style: .cancel, handler: nil)
            certAlert.addAction(ok)
            return certAlert
        }
        
        if (!glacierpublic) {
            switch trustResultType {
            case .proceed, .unspecified:
                certAlert.message = "\(message)\n\n✅ \(VALID_CERTIFICATE_STRING())"
            default:
                let errorMessage = OTRXMPPError.errorString(with: trustResultType) ?? UNKNOWN_ERROR_STRING()
                certAlert.message = "\(message)\n\n❌ \(errorMessage)"
            }
        }
        
        let reject = UIAlertAction(title: REJECT_STRING(), style: .destructive, handler: nil)
        let save = UIAlertAction(title: SAVE_STRING(), style: .default, handler: { alert in
            OTRCertificatePinning.addCertificateData(certData, withHostName: hostname)
            saveHandler(alert)
        })
        
        if (!glacierpublic) { 
            certAlert.addAction(reject)
        }
        certAlert.addAction(save)
        
        return certAlert
    }
}
