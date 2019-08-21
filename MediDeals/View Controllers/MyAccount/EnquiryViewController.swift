//
//  EnquiryViewController.swift
//  MediDeals
//
//  Created by Pankaj Rana on 15/06/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class EnquiryViewController: UIViewController,UITextViewDelegate{

    @IBOutlet weak var venderEmail: DesignableTextField!
    @IBOutlet weak var desc: DesignableTextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.desc.delegate = self
        desc.text = "Enter Message"
        // Do any additional setup after loading the view.
    }
    //MARK:- UITextViewDelegates
    func textViewDidBeginEditing(_ textView: UITextView) {
        if desc.text == "Enter Message" {
            desc.text = ""
            desc.textColor = UIColor.black
        }
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
        }
        return true
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if desc.text == "" {
            desc.text = "Enter Message"
            desc.textColor = UIColor.lightGray
        }
    }

    @IBAction func submit(_ sender: DesignableButton) {
        if venderEmail.text == "" && desc.text == "Enter Message" {
             Utilities.ShowAlertView2(title: "Alert", message: "Please enter all information first", viewController: self)
        }
        else if venderEmail.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your email", viewController: self)
        }
        else if (isValidEmail1(testStr: self.venderEmail.text!) == false)
        {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter the valid email", viewController: self)
        }
        else if desc.text == "Enter Message" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your messsage", viewController: self)
        }else{
            self.addEnquiryAPI()
        }
    }
    
    func isValidEmail1(testStr:String) -> Bool
    {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        
        return emailTest.evaluate(with: self.venderEmail.text)
        
    }
    
    //MARK: Add product API:
    func addEnquiryAPI(){
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["vendor_id" : UserDefaults.standard.value(forKey: "USER_ID") as! String,
                      "vendor_email" : self.venderEmail.text!,
                      "message": self.desc.text!]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.addEnquirie.caseValue,parameters: params){ (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
               
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
                
            } else {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
                self.desc.text = "Enter Message"
                self.venderEmail.text = ""
            }
        }
    }
}
