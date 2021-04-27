//
//  ImageCache.swift
//  Glacier
//
//  Created by Andy Friedman on 12/7/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

@objc class ImageCache: NSObject , NSDiscardableContent {

    @objc public var image: UIImage!

    @objc func beginContentAccess() -> Bool {
        return true
    }

    @objc func endContentAccess() {

    }

    @objc func discardContentIfPossible() {

    }

    @objc func isContentDiscarded() -> Bool {
        return false
    }
}
