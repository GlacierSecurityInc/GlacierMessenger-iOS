//
//  OTRProtocolManager.swift
//  ChatSecureCore
//
//  Created by Chris Ballinger on 1/22/18.
//  Copyright © 2018 Chris Ballinger. All rights reserved.
//

import Foundation
import OTRAssets

public extension OTRProtocolManager {
    #if DEBUG
    /// when OTRBranding.pushStagingAPIURL is nil (during tests) a valid value must be supplied for the integration tests to pass
    private static let pushApiEndpoint: URL = OTRSecrets.pushAPIURL()
    #else
    private static let pushApiEndpoint: URL = OTRSecrets.pushAPIURL()
    #endif
    
    @objc static let encryptionManager = OTREncryptionManager()
    
    @objc static let pushController = PushController(baseURL: OTRProtocolManager.pushApiEndpoint, sessionConfiguration: URLSessionConfiguration.ephemeral)
}
