//
//  Conversation.swift
//  GlacierShare
//
//  Created by Andy Friedman on 12/15/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

import UIKit

@objc final class Conversation : NSObject {
    @objc var key: String?
    @objc var name: String?
    @objc var owner: OTRThreadOwner?
}
