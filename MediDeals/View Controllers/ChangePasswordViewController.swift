//
//  ChangePasswordViewController.swift
//  MediDeals
//
//  Created by SIERRA on 1/2/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class ChangePasswordViewController: UIViewController {
    @IBOutlet weak var txtOldPassword: UITextField!
    @IBOutlet weak var txtNewPassword: UITextField!
    @IBOutlet weak var txtConfrimPassword: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideRightSideMenu()
        txtOldPassword.attributedPlaceholder = NSAttributedString(string:"OLD PASSWORD", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
         txtNewPassword.attributedPlaceholder = NSAttributedString(string:"NEW PASSWORD", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
         txtConfrimPassword.attributedPlaceholder = NSAttributedString(string:"CONFIRM PASSWORD", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    
}
