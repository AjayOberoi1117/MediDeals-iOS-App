//
//  ContactUsViewController.swift
//  MediDeals
//
//  Created by Pankaj Rana on 30/12/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class ContactUsViewController: UIViewController,UITextViewDelegate, UITextFieldDelegate{

    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet var txtViewMessage: UITextView!
    @IBOutlet var txtContactNo: UITextField!
    @IBOutlet var txtEmail: UITextField!
    @IBOutlet var txtName: UITextField!
   
    override func viewDidLoad(){
        super.viewDidLoad()
        Utilities.HideRightSideMenu()
        self.scrollView.isScrollEnabled = false
        txtContactNo.attributedPlaceholder = NSAttributedString(string:"CONTACT NO.", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtEmail.attributedPlaceholder = NSAttributedString(string:"EMAIL", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtName.attributedPlaceholder = NSAttributedString(string:"NAME", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtName.delegate = self
        txtEmail.delegate = self
        txtContactNo.delegate = self
        txtViewMessage.delegate = self
        txtViewMessage.text = "MESSAGE"
        txtViewMessage.textColor = UIColor.white
        // Do any additional setup after loading the view.
    }
    
    @IBAction func btnSubmit(_ sender: UIButton){
        Validation1()
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        print("start editing...")
        self.scrollView.isScrollEnabled = true
    }
    
    //MARK:- UITextViewDelegates
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        if txtViewMessage.text == "MESSAGE" {
            txtViewMessage.text = ""
            txtViewMessage.textColor = UIColor.white
        }
    }
   
    func textViewDidEndEditing(_ textView: UITextView) {
        if txtViewMessage.text.isEmpty {
            txtViewMessage.text = "MESSAGE"
            txtViewMessage.textColor = UIColor.white
        }
    }
    
    //MARK:validation1 login
    func Validation1()
    {
        if txtName.text == "" && txtEmail.text == "" && txtContactNo.text == "" && txtViewMessage.text == "MESSAGE"
        {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter all the fields", viewController: self)
            
        }
        else if txtName.text == ""         {
            Utilities.ShowAlertView2(title: "Alert", message: "Enter your name", viewController: self)
            
        }
        else if txtEmail.text == ""         {
             Utilities.ShowAlertView2(title: "Alert", message: "Enter your email", viewController: self)
         }
        else if txtContactNo.text == ""         {
            Utilities.ShowAlertView2(title: "Alert", message: "Enter your contact number", viewController: self)
        }
        else if txtViewMessage.text == "MESSAGE"
        {
            Utilities.ShowAlertView2(title: "Alert", message: "Enter your message", viewController: self)
            
        }
        else
        {
            self.Validation2()
            // self.sague()
        }
    }
    
    func Validation2()
    {
        if  isValidEmail(testStr: txtEmail.text!) == true
        {
            self.ContactUSAPI()
        }else
        {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter valid email", viewController: self)
         }
    }
    func isValidEmail(testStr:String) -> Bool
    {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        
        return emailTest.evaluate(with: txtEmail.text)
    }
  
    @IBAction func sideMenu(_ sender: Any){
        Utilities.LeftSideMenu()
    }
    
    func ContactUSAPI(){
        //self.showProgress()
        self.addLoadingIndicator()
        self.startAnim()
        let params = [ "name" : self.txtName.text!,
                       "phone" : self.txtContactNo.text!,
                       "email" : self.txtEmail.text!,
                       "message" : self.txtViewMessage.text!,
                       "title": "request"
                       ]
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.contact_us.caseValue, parameters: params) { (response) in
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
                    self.txtName.text = ""
                    self.txtEmail.text = ""
                    self.txtContactNo.text = ""
                    self.txtViewMessage.text = "MESSAGE"
                }))
                self.present(alert, animated: true, completion: nil)
            }
            
        }
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
