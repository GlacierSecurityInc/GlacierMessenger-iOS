//
//  OTRProtocolManager.swift
//  ChatSecureCore
//
//  Created by Chris Ballinger on 1/22/18.
//  Copyright © 2018 Chris Ballinger. All rights reserved.
//

import Foundation

public extension OTRProtocolManager {
    private static let pushApiEndpoint: URL = GlacierInfo.pushAPIURL()
    
    @objc static let encryptionManager = OTREncryptionManager()
    
    @objc static let pushController = PushController(baseURL: OTRProtocolManager.pushApiEndpoint, sessionConfiguration: URLSessionConfiguration.ephemeral)
}
