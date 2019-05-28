//
//  OTPViewController.swift
//  MediDeals
//
//  Created by VLL on 2/18/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class OTPViewController: UIViewController,VPMOTPViewDelegate {
    @IBOutlet var otpView: VPMOTPView!
    @IBOutlet weak var titleLbl: UILabel!
    
    var phnNumber = ""
    var otpNumber = ""
    var otpDigits = ""
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.isNavigationBarHidden = true
        self.titleLbl.text = "Please type the verification code sent to " + phnNumber
        otpView.otpFieldsCount = 4
        otpView.otpFieldDefaultBorderColor = UIColor.gray
        otpView.otpFieldEnteredBorderColor = UIColor.white
        otpView.otpFieldErrorBorderColor = UIColor.red
        otpView.otpFieldBorderWidth = 2
        otpView.delegate = self
        otpView.shouldAllowIntermediateEditing = false
        otpView.otpFieldDisplayType = .square
        // Create the UI
        otpView.initializeUI()
        // Do any additional setup after loading the view.
    }
   
    func shouldBecomeFirstResponderForOTP(otpFieldIndex index: Int) -> Bool {
        return true
    }
    func enteredOTP(otpString: String) {
        print(otpString)
        self.otpNumber = otpString
    }
    
    func hasEnteredAllOTP(hasEntered: Bool) -> Bool {
        return true
    }
    
    @IBAction func otpBtn(_ sender: DesignableButton) {
        if self.otpNumber != ""{
            self.VerifyOTP_API()
        }else{
            Utilities.ShowAlertView2(title: "Alert", message: "Please type verification code first", viewController: self)
        }
    }
    
    @IBAction func resendOTP(_ sender: UIButton) {
        VPMOTPTextField.clearTextInputContextIdentifier("")
        ResendOTP_API()
    }
    @IBAction func backBtn(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
    
    func VerifyOTP_API(){
        showProgress()
        let params = ["user_id" : SingletonVariables.sharedInstace.userId,
                      "otp": self.otpNumber]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.verifyOtp.caseValue, parameters: params) { (response) in
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
                if SingletonVariables.sharedInstace.loginStatus == "yes"{
                    let vc = self.storyboard?.instantiateViewController(withIdentifier: "Home_ViewController") as! Home_ViewController
                    vc.checkSagueActon = "yes"
                    UserDefaults.standard.set(SingletonVariables.sharedInstace.userId, forKey: "USER_ID")
                    self.navigationController?.pushViewController(vc, animated: true)
                }else{
                    let vc = self.storyboard?.instantiateViewController(withIdentifier: "AccountTypeViewController") as! AccountTypeViewController
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            }
            
        }
    }
    func ResendOTP_API(){
        showProgress()
        let params = ["user_id" : SingletonVariables.sharedInstace.userId]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.resendOtp.caseValue, parameters: params) { (response) in
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
              
            }
            
        }
    }
}
