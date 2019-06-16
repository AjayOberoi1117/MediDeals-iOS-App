//  DesignableClass.swift
//  OSODCompany
//  Created by SIERRA on 7/13/18.
//  Copyright © 2018 SIERRA. All rights reserved.


import Foundation
import UIKit
//MARK:===============DesignableButton=====================
@IBDesignable class DesignableButton: UIButton {
    
    @IBInspectable var CornerRadius :CGFloat = 0.0 {
        didSet{self.layer.cornerRadius = CornerRadius}
    }
    
    @IBInspectable var BorderWidth :CGFloat = 0.0 {
         didSet{self.layer.borderWidth = BorderWidth}
    }
   @IBInspectable var BorderColor :UIColor = .clear {
        didSet{ self.layer.borderColor = BorderColor.cgColor}
    }
}
//MARK:===============DesignableView=====================
@IBDesignable class DesignableView: UIView{
    @IBInspectable var CornerRadius: CGFloat = 0.0{
        didSet{self.layer.cornerRadius = CornerRadius}
    }
    @IBInspectable var BorderWidth :CGFloat = 0.0 {
        didSet{self.layer.borderWidth = BorderWidth}
    }
    @IBInspectable var BorderColor :UIColor = .clear {
        didSet{ self.layer.borderColor = BorderColor.cgColor}
    }
}

//MARK:===============DesignableView=====================
@IBDesignable class DesignableTextField: UITextField{
    @IBInspectable var CornerRadius: CGFloat = 0.0{
        didSet{self.layer.cornerRadius = CornerRadius}
    }
    @IBInspectable var BorderWidth :CGFloat = 0.0 {
        didSet{self.layer.borderWidth = BorderWidth}
    }
    @IBInspectable var BorderColor :UIColor = .clear {
        didSet{ self.layer.borderColor = BorderColor.cgColor}
    }
}

//MARK:===============DesignableView=====================
@IBDesignable class DesignableTextView: UITextView{
    @IBInspectable var CornerRadius: CGFloat = 0.0{
        didSet{self.layer.cornerRadius = CornerRadius}
    }
    @IBInspectable var BorderWidth :CGFloat = 0.0 {
        didSet{self.layer.borderWidth = BorderWidth}
    }
    @IBInspectable var BorderColor :UIColor = .clear {
        didSet{ self.layer.borderColor = BorderColor.cgColor}
    }
}
//MARK:===============DesignableCell=====================

@IBDesignable class DesignableImage: UIImageView{
    @IBInspectable var CornerRadius: CGFloat = 0.0{
        didSet{self.layer.cornerRadius = CornerRadius/2}
    }
    @IBInspectable var BorderWidth :CGFloat = 0.0 {
        didSet{self.layer.borderWidth = BorderWidth}
    }
    @IBInspectable var BorderColor :UIColor = .clear {
        didSet{ self.layer.borderColor = BorderColor.cgColor}
    }
 }

//MARK:===============DesignableSearchBar=====================

@IBDesignable class DesignableSearchBar: UISearchBar{
    @IBInspectable var CornerRadius: CGFloat = 0.0{
        didSet{self.layer.cornerRadius = CornerRadius/2}
    }
    @IBInspectable var BorderWidth :CGFloat = 0.0 {
        didSet{self.layer.borderWidth = BorderWidth}
    }
    @IBInspectable var BorderColor :UIColor = .clear {
        didSet{ self.layer.borderColor = BorderColor.cgColor}
    }
}
