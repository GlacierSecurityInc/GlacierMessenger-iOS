//
//  UIAlertController+ChatSecure.swift
//  ChatSecureCore
//
//  Created by Chris Ballinger on 8/1/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

import UIKit

public extension UIAlertController {
    
    /** Returns a cert-pinning alert if needed */
    @objc static func certificateWarningAlert(error: Error, saveHandler: @escaping (_ action: UIAlertAction) -> Void) -> UIAlertController? {
        let nsError = error as NSError
        guard let errorCode = OTRXMPPErrorCode(rawValue: nsError.code),
            errorCode == .sslError,
            let certData = nsError.userInfo[OTRXMPPSSLCertificateDataKey] as? Data,
            let hostname = nsError.userInfo[OTRXMPPSSLHostnameKey] as? String,
            let trustResultTypeValue = nsError.userInfo[OTRXMPPSSLTrustResultKey] as? UInt32,
            let _ = SecTrustResultType(rawValue: trustResultTypeValue) else {
            return nil
        }
        
        let cmessage = "\n\nHeads up! Glacier has been updated. Tap Save to continue."
        let certAlert = UIAlertController(title: "Client Updated", message: cmessage, preferredStyle: .alert)
        
        
        // Bail out if we can't find public key
        guard OTRCertificatePinning.publicKey(withCertData: certData) != nil else {
            certAlert.message = "Glacier could not be updated\n\n"
            let ok = UIAlertAction(title: OK_STRING(), style: .cancel, handler: nil)
            certAlert.addAction(ok)
            return certAlert
        }
        
        let save = UIAlertAction(title: SAVE_STRING(), style: .default, handler: { alert in
            OTRCertificatePinning.addCertificateData(certData, withHostName: hostname)
            saveHandler(alert)
        })
        
        certAlert.addAction(save)
        
        return certAlert
    }
}
