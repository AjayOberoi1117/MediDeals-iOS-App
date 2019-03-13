//
//  RegisterVC2.swift
//  MediDeals
//
//  Created by SIERRA on 2/21/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class RegisterVC2: UIViewController {

    @IBOutlet var txtUserName: UITextField!
    @IBOutlet var txtMobile: UITextField!
    @IBOutlet var txtEmail: UITextField!
    @IBOutlet var txtPassword: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        txtUserName.attributedPlaceholder = NSAttributedString(string:"User name", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        //self.forgotPwdView.isHidden = true
        txtMobile.attributedPlaceholder = NSAttributedString(string:"Mobile", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtEmail.attributedPlaceholder = NSAttributedString(string:"Email (optional)", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        //txtPassword.attributedPlaceholder = NSAttributedString(string:"Password", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        
        // Do any additional setup after loading the view.
    }
    @IBAction func signUpBtn(_ sender: DesignableButton) {
    let vc = self.storyboard?.instantiateViewController(withIdentifier: "OTPViewController") as! OTPViewController
    self.navigationController?.pushViewController(vc, animated: true)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func loginBtn(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
    

}
