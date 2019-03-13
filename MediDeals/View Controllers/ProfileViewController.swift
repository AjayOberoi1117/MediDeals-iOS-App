//
//  ProfileViewController.swift
//  MediDeals
//
//  Created by Pankaj Rana on 30/12/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class ProfileViewController: UIViewController {
    @IBOutlet var txtUserType: UITextField!
    var getProfileData = [getProfile]()
    var editAction = ""
    @IBOutlet var txtShopPlotNo: UITextField!
    @IBOutlet var txtWebsiteUrl: UITextField!
    @IBOutlet var txtCity: UITextField!
    @IBOutlet var txtFissaiNumber: UITextField!
    @IBOutlet var txtLicenseNo: UITextField!
    @IBOutlet var txtGSTNo: UITextField!
    @IBOutlet var txtAddress: UITextField!
    @IBOutlet var txtContact: UITextField!
    @IBOutlet var txtEmail: UITextField!
    @IBOutlet var txtName: UITextField!
    @IBOutlet weak var submitBtn: DesignableButton!
    @IBOutlet var scrollView: UIScrollView!
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideRightSideMenu()
        self.txtName.isUserInteractionEnabled = false
        self.txtAddress.isUserInteractionEnabled = false
        self.txtEmail.isUserInteractionEnabled = false
        self.txtContact.isUserInteractionEnabled = false
        self.txtGSTNo.isUserInteractionEnabled = false
        self.txtLicenseNo.isUserInteractionEnabled = false
        self.txtFissaiNumber.isUserInteractionEnabled = false
        self.txtUserType.isUserInteractionEnabled = false
        self.txtCity.isUserInteractionEnabled = false
        self.txtShopPlotNo.isUserInteractionEnabled = false
        self.txtWebsiteUrl.isUserInteractionEnabled = false
         self.scrollView.isScrollEnabled = false
        txtLicenseNo.attributedPlaceholder = NSAttributedString(string:"LICENSE NO.", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtGSTNo.attributedPlaceholder = NSAttributedString(string:"GST NO.", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtAddress.attributedPlaceholder = NSAttributedString(string:"ADDRESS", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtContact.attributedPlaceholder = NSAttributedString(string:"CONTACT NO.", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtEmail.attributedPlaceholder = NSAttributedString(string:"EMAIL", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        txtName.attributedPlaceholder = NSAttributedString(string:"BUSINESS NAME", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
         // Do any additional setup after loading the view.
        self.submitBtn.isHidden = true
        
        editAction = ""
        //getProfileAPI()
    }
    
    @IBAction func leftMenu(_ sender: UIBarButtonItem) {
        Utilities.LeftSideMenu()
    }
    func getProfileAPI(){
       // self.showProgress()
        self.addLoadingIndicator()
        self.startAnim()
        let params = [ "vendor_id": UserDefaults.standard.value(forKey: "USER_ID") as! String,
                       ]
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.getProfile.caseValue, parameters: params) { (response) in
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
                do {
                    let response = try GetProfileResponse(json: dic.value(forKey: "record") as! [String: Any])
                    self.getProfileData = response.getdata
                    self.txtName.text = self.getProfileData[0].firm_name
                    self.txtAddress.text = self.getProfileData[0].firm_address
                    self.txtEmail.text = self.getProfileData[0].email
                    self.txtLicenseNo.text = self.getProfileData[0].drug_licence
                    self.txtContact.text = self.getProfileData[0].contact_no
                    self.txtFissaiNumber.text = self.getProfileData[0].fssai_no
                    self.txtUserType.text = self.getProfileData[0].user_type
//                    self.txtCity.text = self.getProfileData[0].ci
                    self.txtShopPlotNo.text = self.getProfileData[0].firm_address
                    self.txtWebsiteUrl.text = self.getProfileData[0].website_url
                    //let urlstring = self.getProfileData[0].Profile_Pic
//                    let trimmedString1 = urlstring.replacingOccurrences(of: " ", with: "%20")
//                    let url = NSURL(string: trimmedString1)
//                    self.profileImage.sd_setImage(with: url! as URL, placeholderImage: #imageLiteral(resourceName: "man-user"))
//                    self.profileImage.layer.cornerRadius = self.profileImage.frame.size.height / 2
//                    self.profileImage.clipsToBounds = true
//
//                    UserDefaults.standard.set(urlstring, forKey: "PROFILEIMAGE")
                    UserDefaults.standard.set(self.getProfileData[0].email, forKey: "PROFILEEMAIL")
                    UserDefaults.standard.set(self.getProfileData[0].firm_name, forKey: "PROFILENAME")
                    UserDefaults.standard.synchronize()
                    
                }
                catch {}
            }
            
        }
    }
    @IBAction func submitBtnAct(_ sender: UIButton) {
        editProfileAPI()
    }
    func textFieldDidBeginEditing(_ textField: UITextField) {
        print("start editing...")
        self.scrollView.isScrollEnabled = true
    }
    
    @IBAction func editBtnAct(_ sender: UIBarButtonItem) {
        if self.editAction == ""{
            self.editAction = "yes"
            self.submitBtn.isHidden = false
            self.scrollView.isScrollEnabled = true
            self.txtName.isUserInteractionEnabled = true
            self.txtAddress.isUserInteractionEnabled = true
            self.txtEmail.isUserInteractionEnabled = true
            self.txtContact.isUserInteractionEnabled = true
            self.txtGSTNo.isUserInteractionEnabled = true
            self.txtLicenseNo.isUserInteractionEnabled = true
            self.txtFissaiNumber.isUserInteractionEnabled = true
            self.txtUserType.isUserInteractionEnabled = true
            self.txtCity.isUserInteractionEnabled = true
            self.txtShopPlotNo.isUserInteractionEnabled = true
            self.txtWebsiteUrl.isUserInteractionEnabled = true
  
        }else{
            self.editAction = ""
            self.scrollView.isScrollEnabled = false
            self.txtName.isUserInteractionEnabled = false
            self.txtAddress.isUserInteractionEnabled = false
            self.txtEmail.isUserInteractionEnabled = false
            self.txtContact.isUserInteractionEnabled = false
            self.txtGSTNo.isUserInteractionEnabled = false
            self.txtLicenseNo.isUserInteractionEnabled = false
            self.txtFissaiNumber.isUserInteractionEnabled = false
            self.txtUserType.isUserInteractionEnabled = false
            self.txtCity.isUserInteractionEnabled = false
            self.txtShopPlotNo.isUserInteractionEnabled = false
            self.txtWebsiteUrl.isUserInteractionEnabled = false
        }
    }
    func editProfileAPI(){
       // self.showProgress()
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["vendor_id":UserDefaults.standard.value(forKey: "USER_ID") as! String,
                      "firm_name": self.txtName.text!,
                          "firm_address":self.txtAddress.text!,
                          "contact_no":self.txtContact.text!,
                          "email":self.txtEmail.text!,
                          "gst_number":self.txtGSTNo.text!,
                          "drug_licence":self.txtLicenseNo.text!]
            print(params)
            NetworkingService.shared.getData(PostName: APIEndPoint.userCase.editProfile.caseValue, parameters: params) { (response) in
                print(response)
                let dic = response as! NSDictionary
                print(dic)
                if (dic.value(forKey: "status") as? String == "0")
                {
                    self.hideProgress()
                    self.stopAnim()
                    Utilities.ShowAlertView2(title: "Alert",message: dic.value(forKey: "message") as! String, viewController: self)
                }
                else
                {
                    self.hideProgress()
                    self.stopAnim()
                   self.editAction = ""
                   self.submitBtn.isHidden = true
                    self.scrollView.isScrollEnabled = false
                    self.txtName.isUserInteractionEnabled = false
                    self.txtAddress.isUserInteractionEnabled = false
                    self.txtEmail.isUserInteractionEnabled = false
                    self.txtContact.isUserInteractionEnabled = false
                    self.txtGSTNo.isUserInteractionEnabled = false
                    self.txtLicenseNo.isUserInteractionEnabled = false
//                    self.disableIntraction()
                    Utilities.ShowAlertView2(title: "Message",message: dic.value(forKey: "message") as! String, viewController: self)
                    self.getProfileAPI()
                    
                }
                
            }
        }
}
