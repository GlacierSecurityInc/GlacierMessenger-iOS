//
//  FilePreviewView.swift
//  ChatSecureCore
//
//  Created by Andy Friedman on 6/14/19.
//  Copyright © 2019 Glacier. All rights reserved.

public class FilePreviewView: UIView {
    
    @IBOutlet weak var clickToOpenLabel: UILabel!
    @IBOutlet weak var filenameLabel: UILabel!
    @IBOutlet weak var fileImageLabel: UILabel!
    
    @objc public func setFile(_ filename: String?) {
        filenameLabel.text = filename
    }
    
    @objc public func setOutgoing(_ outgoing: Bool) {
        if (outgoing) {
            filenameLabel.textColor = UIColor.white
            clickToOpenLabel.textColor = UIColor.white
            fileImageLabel.textColor = UIColor.white
        }
    }
}

