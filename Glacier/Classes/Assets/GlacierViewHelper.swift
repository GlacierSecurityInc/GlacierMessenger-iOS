//
//  GlacierViewHelper.swift
//
//  Created by Andy Friedman on 6/15/20.
//  Copyright © 2020 Glacier Security. All rights reserved.
//

import UIKit


extension UIView {
    
    /// Helper for loading nibs from the OTRResources bundle
    @objc public static func glacierViewFromNib() -> Self? {
        guard let nibName = self.gnibName else {
            return nil
        }
        return glacierViewFromNib(nibName: nibName)
    }
    
    private static func glacierViewFromNib<T>(nibName: String) -> T? {
        guard let nibName = self.gnibName else {
            return nil
        }
        return GlacierInfo.resourcesBundle.loadNibNamed(nibName, owner: nil, options: nil)?.first as? T
    }
    
    private static var gnibName: String? {
        return NSStringFromClass(self).components(separatedBy: ".").last
    }
}
