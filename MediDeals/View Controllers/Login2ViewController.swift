//
//  Login2ViewController.swift
//  MediDeals
//
//  Created by VLL on 2/18/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class Login2ViewController: UIViewController,UITextFieldDelegate {
    @IBOutlet weak var EmailView: UIView!
    @IBOutlet weak var txtPasswrd: UITextField!
    @IBOutlet weak var txtEmail: UITextField!
    @IBOutlet var hiddenView: UIView!
    @IBOutlet weak var logo: UIImageView!
    @IBOutlet weak var txtForgotEmil: UITextField!
    @IBOutlet weak var forgotPwdView: DesignableView!
    @IBOutlet weak var logoImg: UIImageView!
    @IBOutlet weak var sendOTPBtn: DesignableButton!
    
    var tapGesture = UITapGestureRecognizer()
    var checkTxtAct = ""
    override func viewDidLoad() {
        super.viewDidLoad()
        txtEmail.delegate = self
        self.EmailView.isHidden = true
        self.sendOTPBtn.isHidden = false
        self.hiddenView.isHidden = true
        //self.forgotPwdView.isHidden = true
        txtEmail.attributedPlaceholder = NSAttributedString(string:"Mobile", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        //self.forgotPwdView.isHidden = true
        txtPasswrd.attributedPlaceholder = NSAttributedString(string:"Password", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        
        self.hiddenView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTappedOnCircularView1)))
        self.sendOTPBtn.isHidden = true
        
        if UserDefaults.standard.value(forKey: "USER_ID") == nil
        {
            print("user are not logged in...")
        }
        else
        {
            //self.sague()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(Login_ViewController.methodOfReceivedNotification), name: NSNotification.Name(rawValue: "GMAIL_NOTI"), object: nil)
        // Do any additional setup after loading the view.
    }
    
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField == self.txtEmail{
            if string.isNumericValue == true{
                print("numbric")
                self.checkTxtAct = "number"
                let length = (txtEmail.text?.count)! - range.length + string.count
                print("lenght",length)
                if length == 1{
                    let num : String = self.formatNumber(mobileNo: txtEmail.text!)
                    txtEmail.text = "+91- " + num
                }
                else if length == 15{
                    self.sendOTPBtn.isHidden = false
                    self.EmailView.isHidden = true
                }else{
                    self.sendOTPBtn.isHidden = true
                    self.EmailView.isHidden = true
                }
            }else{
                let length = (txtEmail.text?.count)! - range.length + string.count
                print("lenght",length)
                if length == 1{
                    let num : String = self.formatNumber(mobileNo: txtEmail.text!)
                    txtEmail.text = "+91- " + num
                }
                else if length == 15{
                    self.sendOTPBtn.isHidden = false
                    self.EmailView.isHidden = true
                }else{
                    self.sendOTPBtn.isHidden = true
                    self.EmailView.isHidden = true
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
//    func textFieldDidBeginEditing(_ textField: UITextField) {
//        if textField == self.txtEmail{
//            let num : String = self.formatNumber(mobileNo: txtEmail.text!)
//            txtEmail.text = "+91- " + num
//
//        }
//    }
//    func textFieldDidEndEditing(_ textField: UITextField) {
//        if textField == self.txtEmail{
//            let num : String = self.formatNumber(mobileNo: txtEmail.text!)
//            txtEmail.text = "+91- " + num
//
//        }
//    }
   
    func formatNumber(mobileNo: String) -> String{
        var str : NSString = mobileNo as NSString
        str = str.replacingOccurrences(of: "+91- ", with: "") as NSString
        return str as String
    }
    

    @objc func methodOfReceivedNotification() {
        print("RECEIVED ANY NOTIFICATION")
        self.sague()
    }
    func sague(){
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "Home_ViewController") as! Home_ViewController
        vc.checkSagueActon = "yes"
        self.navigationController?.pushViewController(vc, animated: false)
    }
    @objc func didTappedOnCircularView1(){
        print("someone tap me...")
        hiddenView.isHidden = true
       // forgotPwdView.isHidden = true
    }
    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.isNavigationBarHidden = true
        //  self.logo.layer.cornerRadius = self.logo.frame.size.height / 2
        // self.logo.clipsToBounds = true
    }
    @IBAction func login_act(_ sender: UIButton) {
        //self.validations()
        loginAPI()
        
//        let vc = self.storyboard?.instantiateViewController(withIdentifier: "OTPViewController") as! OTPViewController
//        if self.checkTxtAct == "number"{
//        vc.phnNumber = txtEmail.text!
//        }else{
//            vc.phnNumber = "+91 - 1231231231"
//        }
//        self.navigationController?.pushViewController(vc, animated: false)
    }
    @IBAction func sendPassAct(_ sender: UIButton) {
        if txtForgotEmil.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your email", viewController: self)
        }
        else if (isValidEmail1(testStr: self.txtForgotEmil.text!) == false)
        {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter the valid email", viewController: self)
        }
        else{
            ForgotPasswordAPI()
        }
    }
    func isValidEmail1(testStr:String) -> Bool
    {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        
        return emailTest.evaluate(with: self.txtForgotEmil.text)
        
    }
    
    func loginAPI(){
    showProgress()
        let a = txtEmail.text!.replacingOccurrences(of: "- ", with: " ")
        let toArray = a.components(separatedBy: " ")
        let countryCode = toArray[0]
        let phn = toArray[1]
        let params = [ "contact_no" : phn,
                       "country_code" : countryCode]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.newLogin.caseValue, parameters: params) { (response) in
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
                let secondViewController = self.storyboard?.instantiateViewController(withIdentifier: "Home_ViewController") as! Home_ViewController
                secondViewController.checkSagueActon = "yes"
                let user_id = "\(dic.value(forKeyPath: "id") as! String)"
                // let user_accessToken = dic.value(forKeyPath: "token") as! String
                UserDefaults.standard.set(user_id, forKey: "USER_ID")
                //UserDefaults.standard.set(user_accessToken, forKey: "TOKEN")
                UserDefaults.standard.synchronize()
                self.navigationController?.pushViewController(secondViewController, animated: true)
                
            }
            
        }
    }
    
    
    
    @IBAction func forgotPassword(_ sender: UIButton){
        forgotPwdView.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        UIView.animate(withDuration: 0.9, // your duration
            delay: 0,
            usingSpringWithDamping: 0.2,
            initialSpringVelocity: 6.0,
            animations:{
                self.forgotPwdView.transform = .identity
        },
            completion: { _ in
                // Implement your awesome logic here.
        })
        let blurEffect = UIBlurEffect(style: UIBlurEffectStyle.light)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = view.bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hiddenView.addSubview(blurEffectView)
        hiddenView.isHidden = false
        forgotPwdView.isHidden = false
    }
    
    func ForgotPasswordAPI(){
        //self.showProgress()
        self.addLoadingIndicator()
        self.startAnim()
        let params = [ "email" : self.txtForgotEmil.text!]
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.forgotPassword.caseValue, parameters: params) { (response) in
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
                    self.hiddenView.isHidden = true
                    
                    
                    //self.forgotPwdView.isHidden = true
                    
                }))
                self.present(alert, animated: true, completion: nil)
            }
            
        }
    }
    @IBAction func signUpAct(_ sender: UIButton) {
    }
}
extension String {
    var isNumericValue: Bool {
        return !isEmpty && range(of: "[^0-9]", options: .regularExpression) == nil
    }
    var isAlphabetValue: Bool {
        return !isEmpty && range(of: "[^a-zA-Z]", options: .regularExpression) == nil
    }
}
