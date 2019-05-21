//
//  RegisterVC2.swift
//  MediDeals
//
//  Created by SIERRA on 2/21/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class RegisterVC2: UIViewController,UITextFieldDelegate{

    @IBOutlet weak var signUpBtn: DesignableButton!
    @IBOutlet var txtUserName: UITextField!
    @IBOutlet var txtMobile: UITextField!
    @IBOutlet var txtEmail: UITextField!
    @IBOutlet var txtPassword: UITextField!
    var checkTxtAct = ""
    override func viewDidLoad() {
        super.viewDidLoad()
        txtMobile.delegate = self
        signUpBtn.isHidden = true
        txtUserName.attributedPlaceholder = NSAttributedString(string:"User name", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        //self.forgotPwdView.isHidden = true
        txtMobile.attributedPlaceholder = NSAttributedString(string:"Mobile", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtEmail.attributedPlaceholder = NSAttributedString(string:"Email", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        //txtPassword.attributedPlaceholder = NSAttributedString(string:"Password", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        
        // Do any additional setup after loading the view.
    }
    
    @IBAction func signUpBtn(_ sender: DesignableButton) {
        if self.txtEmail.text != ""{
            if (isValidEmail1(testStr: self.txtEmail.text!) == false)
            {
                Utilities.ShowAlertView2(title: "Alert", message: "Please enter the valid email", viewController: self)
            }
            else{
                RegisterAPI()
            }
        }else{
           Utilities.ShowAlertView2(title: "Alert", message: "Please enter the valid email", viewController: self)
        }
        
//    let vc = self.storyboard?.instantiateViewController(withIdentifier: "OTPViewController") as! OTPViewController
//    self.navigationController?.pushViewController(vc, animated: true)
    }
    func isValidEmail1(testStr:String) -> Bool
    {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        
        return emailTest.evaluate(with: testStr)
        
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField == self.txtMobile{
            if string.isNumericValue == true{
                print("numbric")
                self.checkTxtAct = "number"
                let length = (txtMobile.text?.count)! - range.length + string.count
                print("lenght",length)
                if length == 1{
                    let num : String = self.formatNumber(mobileNo: txtMobile.text!)
                    txtMobile.text = "+91- " + num
                }
                else if length == 15{
                    self.signUpBtn.isHidden = false
                }else{
                    self.signUpBtn.isHidden = true
                }
            }else{
                let length = (txtMobile.text?.count)! - range.length + string.count
                print("lenght",length)
                if length == 1{
                    let num : String = self.formatNumber(mobileNo: txtMobile.text!)
                    txtMobile.text = "+91- " + num
                }
                else if length == 15{
                    self.signUpBtn.isHidden = false
                }else{
                    self.signUpBtn.isHidden = true
                }
                //                if string.isAlphabetValue == true{
                //                    self.checkTxtAct = ""
                //                    self.sendOTPBtn.isHidden = true
                //                    self.EmailView.isHidden = false
                //                }else{
                //                    self.sendOTPBtn.isHidden = true
                //                    self.EmailView.isHidden = true
                //                }
            }
            
        }
        return true
    }
    
    func formatNumber(mobileNo: String) -> String{
        var str : NSString = mobileNo as NSString
        str = str.replacingOccurrences(of: "+91- ", with: "") as NSString
        return str as String
    }
    @IBAction func loginBtn(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
    func RegisterAPI(){
        showProgress()
        let a = txtMobile.text!.replacingOccurrences(of: "- ", with: " ")
        let toArray = a.components(separatedBy: " ")
        let countryCode = toArray[0]
        let phn = toArray[1]
        let params = ["user_name" : txtUserName.text!,
                      "contact_no" : phn,
                       "country_code" : countryCode,
                       "email": txtEmail.text!]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.newRegister.caseValue, parameters: params) { (response) in
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
                let vc = self.storyboard?.instantiateViewController(withIdentifier: "OTPViewController") as! OTPViewController
                vc.phnNumber = self.txtMobile.text!
                let user_id = "\(dic.value(forKeyPath: "id") as! String)"
                // let user_accessToken = dic.value(forKeyPath: "token") as! String
                UserDefaults.standard.set(user_id, forKey: "USER_ID")
                //UserDefaults.standard.set(user_accessToken, forKey: "TOKEN")
                UserDefaults.standard.synchronize()
                self.navigationController?.pushViewController(vc, animated: true)
                
            }
            
        }
    }

}
