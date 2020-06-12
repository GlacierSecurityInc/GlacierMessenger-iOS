//
//  OTRCircleButton.swift
//  Created by Blue Star on 4/16/20.
//  Copyright © 2020 Glacier security. All rights reserved.

import UIKit

class CircleButton: UIButton {

    // MARK: - Properties
    
    public var deselectedColor: UIColor = .darkGray
    public var selectedColor: UIColor = .white
    
    public var deselectedTextColor: UIColor = .white
    public var selectedTextColor: UIColor = .darkGray
    
    // MARK: - Initialization
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    public required init?(coder aDecorder: NSCoder) {
        super.init(coder: aDecorder)
        initialize()
    }
    
    private func initialize() {
        self.layer.cornerRadius = 32
        //self.clipsToBounds = true
        
        isSelected = false
        setFillState()
    }
    
    // MARK: - Private methods
    
    private func setFillState() {
        if isSelected {
            //self.titleLabel?.textColor = selectedTextColor
            self.tintColor = selectedTextColor
            self.backgroundColor = selectedColor
        } else {
            //self.titleLabel?.textColor = deselectedTextColor
            self.tintColor = deselectedTextColor
            self.backgroundColor = deselectedColor
        }
    }
    
    // MARK: - Overridden methods
    
    override public func layoutSubviews() {
        self.layer.cornerRadius = self.bounds.height / 2
    }
    
    override public var isSelected: Bool {
        didSet {
            setFillState()
        }
    }
}
