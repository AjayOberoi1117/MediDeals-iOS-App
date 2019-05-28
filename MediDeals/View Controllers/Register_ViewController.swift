//
//  Register_ViewController.swift
//  MediDeals
//
//  Created by Pankaj Rana on 27/12/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class Register_ViewController: UIViewController {
    @IBOutlet weak var txtBusinessName: UITextField!
    @IBOutlet weak var txtAccountType: UITextField!
    @IBOutlet weak var txtShopNO: UITextField!
    @IBOutlet weak var txtStreetName: UITextField!
    @IBOutlet weak var txtCity: UITextField!
    @IBOutlet weak var txtLicenceNO: UITextField!
    @IBOutlet weak var txtGSTNO: UITextField!
    @IBOutlet weak var txtContactNO: UITextField!
    @IBOutlet weak var txtEmail: UITextField!
    @IBOutlet weak var txtPassword: UITextField!
   
    var AccType = [String]()
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideLeftSideMenu()
        Utilities.HideRightSideMenu()
//        txtEmail.attributedPlaceholder = NSAttributedString(string:"EMAIL", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
//        txtPassword.attributedPlaceholder = NSAttributedString(string:"PASSWORD", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtBusinessName.attributedPlaceholder = NSAttributedString(string:"BUSINESS NAME", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        //txtAccountType.attributedPlaceholder = NSAttributedString(string:"ACCOUNT TYPE", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtShopNO.attributedPlaceholder = NSAttributedString(string:"SHOP NO./PLOT NO.", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtStreetName.attributedPlaceholder = NSAttributedString(string:"STREET NAME", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtCity.attributedPlaceholder = NSAttributedString(string:"CITY", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtLicenceNO.attributedPlaceholder = NSAttributedString(string:"LICENCE NUMBER", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtGSTNO.attributedPlaceholder = NSAttributedString(string:"GST NUMBER", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
//        txtContactNO.attributedPlaceholder = NSAttributedString(string:"CONTACT NUMBER", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        
        AccType = ["WholeSeller","Retailer","PCD Company","Third Party Manufacture","FMCG","Doctor"]
       
    }
    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.isNavigationBarHidden = true
    }
    @IBAction func SignInAct(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    @IBAction func AccountType_bnt(_ sender: UIButton) {
        let controller = UIAlertController(title: "Choose an Account Type", message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        controller.view.tintColor = UIColor.black
        let closure = { (action: UIAlertAction!) -> Void in
            let index = controller.actions.index(of: action)
            if index != nil {
                NSLog("Index: \(index!)")
                print(self.AccType[index!])
                let selected_type = self.AccType[index!]
               self.txtAccountType.text = selected_type
            }
        }
        for i in 0 ..< self.AccType.count { controller.addAction(UIAlertAction(title: self.AccType[i], style: .default, handler: closure))
            // selected_Year = self.yearsArr[i] as? String
            
        }
        controller.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: nil))
        present(controller, animated: true, completion: nil)
    }
    
   
    func validations() {
        if self.txtBusinessName.text == "" && self.txtShopNO.text == "" && self.txtStreetName.text == "" && self.txtLicenceNO.text == "" && self.txtGSTNO.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter all fields", viewController: self)
        }
        else if txtBusinessName.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your business name", viewController: self)
        }
        else if txtShopNO.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your shop no/plot no", viewController: self)
        }
        else if txtStreetName.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your street name", viewController: self)
        }
        else if txtCity.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your city name", viewController: self)
        }
//        else if txtLicenceNO.text == "" {
//            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your licence number", viewController: self)
//        }
//        else if txtGSTNO.text == "" {
//            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your GST number", viewController: self)
//        }
       
        else {
            self.registerAPI()
        }
    }
    func emailValidation2(){
        if (isValidEmail(testStr: self.txtEmail.text!) == true)
        {
            self.registerAPI()
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
    
    @IBAction func registerAction(_ sender: UIButton) {
        self.validations()
        
    }
    func registerAPI(){
        self.showProgress()
        
        let params = ["user_id": UserDefaults.standard.value(forKey: "USER_ID") as! String,
                      "user_type":SingletonVariables.sharedInstace.accountType,
                      "cat_id":SingletonVariables.sharedInstace.AccountCategory,
                      "firm_name":txtBusinessName.text!,
                      "firm_address1":txtShopNO.text!,
                    "firm_address2":txtStreetName.text!,
                    "firm_address3":txtCity.text!,
                    "drug_licence":txtLicenceNO.text!,
                    "gst_number":txtGSTNO.text!]
        
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.addInformation.caseValue, parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.hideProgress()
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: (dic.value(forKey: "message") as? String)!, viewController: self)
            }
            else
            {
                self.hideProgress()
                self.stopAnim()
                let alert = UIAlertController(title: "Message", message: "Register successfully done", preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: {action -> Void in
                    print("action are work....")
                    self.sague()
                    
                }))
                
                self.present(alert, animated: true, completion: nil)
            }
        }
        
    }
    func sague(){
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "Home_ViewController") as! Home_ViewController
        UserDefaults.standard.set(SingletonVariables.sharedInstace.userId, forKey: "USER_ID")
        vc.checkSagueActon = "yes"
        self.navigationController?.pushViewController(vc, animated: true)
    }
}
