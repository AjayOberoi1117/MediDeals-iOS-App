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
    
    @IBAction func SubbmitBtn(_ sender: DesignableButton) {
        if txtOldPassword.text == "" && txtNewPassword.text == "" && txtConfrimPassword.text == ""
        {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter all the fields", viewController: self)
            
        }
        else if txtOldPassword.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Enter your old password", viewController: self)
        }
        else if txtNewPassword.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Enter your new password", viewController: self)
        }
        else if txtConfrimPassword.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Enter your confirm password", viewController: self)
        }
        else if txtConfrimPassword.text != txtNewPassword.text{
            Utilities.ShowAlertView2(title: "Alert", message: "Confirm password must be same as New password", viewController: self)
        }
        else{
            ChangePassword_API()
        }
    }
    
    func ChangePassword_API(){
        //self.showProgress()
        self.addLoadingIndicator()
        self.startAnim()
        let params = [ "vendor_id" : UserDefaults.standard.value(forKey: "USER_ID") as! String,
                       "old_password" : self.txtOldPassword.text!,
                       "new_password" : self.txtNewPassword.text!
        ]
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.changePassword.caseValue, parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.hideProgress()
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            }
            else
            {
                self.hideProgress()
                self.stopAnim()
                let alert = UIAlertController(title: "Message", message: (dic.value(forKey: "message") as! String), preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: {action -> Void in
                    print("action are work....")
                    self.txtOldPassword.text = ""
                    self.txtNewPassword.text = ""
                    self.txtConfrimPassword.text = ""
                  
                }))
                self.present(alert, animated: true, completion: nil)
            }
            
        }
    }
}
