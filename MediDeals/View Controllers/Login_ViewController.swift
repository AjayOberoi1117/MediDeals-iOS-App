//
//  Login_ViewController.swift
//  MediDeals
//
//  Created by Pankaj Rana on 27/12/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class Login_ViewController: UIViewController {
    @IBOutlet weak var txtEmail: UITextField!
    @IBOutlet var hiddenView: UIView!
    @IBOutlet weak var logo: UIImageView!
    @IBOutlet weak var txtPassword: UITextField!
    @IBOutlet weak var txtForgotEmil: UITextField!
    @IBOutlet weak var forgotPwdView: DesignableView!
    @IBOutlet weak var logoImg: UIImageView!
   
    var tapGesture = UITapGestureRecognizer()
    var gmailuserdictionary = [String : Any]()
    var userid = String()
    var dictFb:NSDictionary!
    var dictTweet:NSDictionary!
    var fb_id = String()
    var fb_type = String()
    var fb_email = String()
    var fb_firstname = String()
    var fb_lastname = String()
    var fb_gender = String()
    var fb_userimage:String!
    var tweet_id = String()
    var tweet_email = String()
    var tweet_name = String()
    var firstname = String()
    var lastname = String()
    var logintype = String()
     override func viewDidLoad() {
        super.viewDidLoad()
  // Do any additional setup after loading the view.
        Utilities.HideLeftSideMenu()
        Utilities.HideRightSideMenu()
        self.hiddenView.isHidden = true
        self.forgotPwdView.isHidden = true
        txtEmail.attributedPlaceholder = NSAttributedString(string:"EMAIL", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white])
        txtPassword.attributedPlaceholder = NSAttributedString(string:"PASSWORD", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white])
        txtForgotEmil.attributedPlaceholder = NSAttributedString(string:"EMAIL", attributes: [NSAttributedString.Key.foregroundColor: UIColor.white])
        self.hiddenView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTappedOnCircularView1)))
        
        if UserDefaults.standard.value(forKey: "USER_ID") == nil
        {
            print("user are not logged in...")
        }
        else
        {
            self.sague()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(Login_ViewController.methodOfReceivedNotification), name: NSNotification.Name(rawValue: "GMAIL_NOTI"), object: nil)
    }
    
    @objc func methodOfReceivedNotification() {
        print("RECEIVED ANY NOTIFICATION")
        self.sague()
    }
   
    @objc func didTappedOnCircularView1(){
        print("someone tap me...")
        hiddenView.isHidden = true
        forgotPwdView.isHidden = true
    }
    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.isNavigationBarHidden = true
      //  self.logo.layer.cornerRadius = self.logo.frame.size.height / 2
       // self.logo.clipsToBounds = true
    }
    @IBAction func login_act(_ sender: UIButton) {
        self.validations()
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
        let blurEffect = UIBlurEffect(style: UIBlurEffect.Style.light)
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = view.bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hiddenView.addSubview(blurEffectView)
        hiddenView.isHidden = false
        forgotPwdView.isHidden = false
    }
    
    @IBAction func sendBtn(_ sender: UIButton) {
    }
    func sague(){
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "Home_ViewController") as! Home_ViewController
        vc.checkSagueActon = "yes"
        self.navigationController?.pushViewController(vc, animated: false)
    }
    
    
    func validations() {
        if self.txtEmail.text == "" && self.txtPassword.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter all fields", viewController: self)
        }
        else if txtEmail.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your email", viewController: self)
        }
        else if (isValidEmail(testStr: self.txtEmail.text!) == false)
        {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter the valid email", viewController: self)
        }
            
        else if txtPassword.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your password", viewController: self)
            
        }else if (txtPassword.text?.count)! < 6 {
            Utilities.ShowAlertView2(title: "Alert", message: "Password should be greater than six characters", viewController: self)
        }
        else {
            emailValidation2()
        }
    }
    func emailValidation2(){
        if (isValidEmail(testStr: self.txtEmail.text!) == true)
        {
            self.loginAPI()
        }
        else{
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter the valid email", viewController: self)
        }
    }
    
    func isValidEmail(testStr:String) -> Bool
    {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        
        return emailTest.evaluate(with: self.txtEmail.text)
        
    }
    func isValidEmail1(testStr:String) -> Bool
    {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        
        return emailTest.evaluate(with: self.txtForgotEmil.text)
        
    }
    func loginAPI(){
        self.addLoadingIndicator()
        self.startAnim()
        let params = [ "email" : self.txtEmail.text!,
                       "password": self.txtPassword.text!
        ]
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.userLogin.caseValue, parameters: params) { (response) in
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
                let user_id = "\(dic.value(forKeyPath: "vendor_id") as! String)"
               // let user_accessToken = dic.value(forKeyPath: "token") as! String
                UserDefaults.standard.set(user_id, forKey: "USER_ID")
                //UserDefaults.standard.set(user_accessToken, forKey: "TOKEN")
                UserDefaults.standard.synchronize()
                self.navigationController?.pushViewController(secondViewController, animated: true)
                
            }
            
        }
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
                let alert = UIAlertController(title: "Message", message: (dic.value(forKey: "message") as! String), preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: {action -> Void in
                    print("action are work....")
                    self.hiddenView.isHidden = true
                    self.forgotPwdView.isHidden = true
                    
                }))
                 self.present(alert, animated: true, completion: nil)
               }
            
        }
    }
}
