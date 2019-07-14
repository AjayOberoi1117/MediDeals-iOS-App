//
//  AddProductsVC.swift
//  MediDeals
//
//  Created by Apple on 05/06/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class AddProductsVC: UIViewController,LBZSpinnerDelegate,UINavigationControllerDelegate, UIImagePickerControllerDelegate,UITextViewDelegate{

    @IBOutlet weak var txtProductName: DesignableTextField!
    @IBOutlet weak var txtViewDescription: DesignableTextView!
    @IBOutlet weak var txtChooseFile: UITextField!
    @IBOutlet weak var btnChooseFile: UIButton!
    @IBOutlet weak var txtMaxRetailPrice: DesignableTextField!
    @IBOutlet weak var txtDiscPrice: DesignableTextField!
    @IBOutlet weak var txtTotalDiscPrice: DesignableTextField!
    @IBOutlet weak var txtQuantity: DesignableTextField!
    @IBOutlet weak var txtMinOrderQuantity: DesignableTextField!
    @IBOutlet weak var txtCompanyName: DesignableTextField!
    @IBOutlet weak var chooseProduct: LBZSpinner!
    @IBOutlet weak var productImg: UIImageView!
    
    var spinnerCode : LBZSpinner!
    var categoryName = ["ALLOPATHIC", "AYURVEDIC", "FMCG", "PCD COMPANIES/3RD PARTY", "SURGICAL GOODS"]
    var imagePicker:UIImagePickerController?=UIImagePickerController()
    var imageData = Data()
    var productImage = UIImage()
    var categoryID = ["1","2","3","4","5"]
    var selectedId = ""
    override func viewDidLoad() {
        super.viewDidLoad()
        chooseProduct.delegate = self
        chooseProduct.updateList(categoryName)
        productImg.isHidden = true
        txtViewDescription.delegate = self
        txtViewDescription.text = "Enter product description"
        txtViewDescription.textColor = UIColor.lightGray
        // Do any additional setup after loading the view.
    }
    func spinnerChoose(_ spinner: LBZSpinner, index: Int, value: String) {
        var spinnerName = ""
        if spinner == chooseProduct { spinnerName = "" }
        if spinner == chooseProduct {
            print("Spinner : \(spinnerName) : { Index : \(index) - \(value) }")
          selectedId = categoryID[index]
        }
        
    }
    
    //MARK:- UITextViewDelegates
    func textViewDidBeginEditing(_ textView: UITextView) {
        if txtViewDescription.text == "Enter product description" {
            txtViewDescription.text = ""
            txtViewDescription.textColor = UIColor.black
        }
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
        }
        return true
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if txtViewDescription.text == "" {
            txtViewDescription.text = "Enter product description"
            txtViewDescription.textColor = UIColor.lightGray
        }
    }
    @IBAction func chooseFileBtn(_ sender: Any) {
        CameraActionSheet()
    }
   
    @IBAction func uploadProduct(_ sender: Any) {
        validations()
    }
 
    //MARK: Action Sheet to open camera and gallery
    func CameraActionSheet(){
        let optionMenu = UIAlertController(title: nil, message: "Choose Option", preferredStyle: .actionSheet)
        let TakeAction = UIAlertAction(title: "Take Photo", style: .default, handler: {
            (alert: UIAlertAction!) -> Void in
            self.opencamera()
        })
        let ChooseAction = UIAlertAction(title: "Choose Photo", style: .default, handler: {
            (alert: UIAlertAction!) -> Void in
            self.openGallery()
        })
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: {
            (alert: UIAlertAction!) -> Void in
        })
        // Add the actions
        imagePicker?.delegate = self
        optionMenu.addAction(TakeAction)
        optionMenu.addAction(ChooseAction)
        optionMenu.addAction(cancelAction)
        self.present(optionMenu, animated: true, completion: nil)
    }
    
    //MARK: Function to open Camera
    func opencamera()
    {
        if UIImagePickerController .isSourceTypeAvailable(UIImagePickerController.SourceType.camera) {
            imagePicker!.delegate = self
            imagePicker!.sourceType = UIImagePickerController.SourceType.camera
            imagePicker!.allowsEditing = true
            imagePicker!.cameraCaptureMode = UIImagePickerController.CameraCaptureMode.photo;
            self.present(imagePicker!, animated: true, completion: nil)
        }else{
            Utilities.ShowAlertView2(title: "Warning", message: "There is some problem to open Camera...", viewController: self)
        }
    }
    //MARK: Function to open Gallery
    
    func openGallery()
    {
        if UIImagePickerController .isSourceTypeAvailable(UIImagePickerController.SourceType.photoLibrary) {
            imagePicker!.delegate = self
            imagePicker!.sourceType = UIImagePickerController.SourceType.photoLibrary;
            imagePicker!.allowsEditing = true
            self.present(imagePicker!, animated: true, completion: nil)
        }
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let image = info[.editedImage] as? UIImage else {
            return
        }
        productImg.image = image
        productImage = image
        imageData = image.jpegData(compressionQuality: 0.2)!
        productImg.isHidden = false
        txtChooseFile.isHidden = true
        self.txtChooseFile.text = "image"
        self.dismiss(animated: true, completion: nil)
    }
    
    func validations() {
        if self.txtProductName.text == "" && self.txtViewDescription.text == "Enter product description" && self.txtChooseFile.text == "" && self.txtMaxRetailPrice.text == "" && self.txtDiscPrice.text == ""  && self.txtTotalDiscPrice.text == "" && self.txtQuantity.text == ""  && self.txtMinOrderQuantity.text == "" && self.txtCompanyName.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter all product information first", viewController: self)
        }
        else if txtProductName.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter product name", viewController: self)
        }
        else if txtViewDescription.text == "Enter product description" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter product description", viewController: self)
        }
        else if selectedId == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Please choose product category first", viewController: self)
        }
        else if txtChooseFile.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please choose a product image file", viewController: self)
        }
        else if self.txtMaxRetailPrice.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter product max. retail price", viewController: self)
        }
        else if txtDiscPrice.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter product discount price", viewController: self)
        }
        else if txtTotalDiscPrice.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter product total discount price", viewController: self)
        }
        else if self.txtQuantity.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter product quantity", viewController: self)
        }
        else if txtMinOrderQuantity.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter product minimum order qunatity", viewController: self)
        }
        else if self.txtCompanyName.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter your company name", viewController: self)
        }
        else {
            self.addProductAPI()
        }
    }
    
    //MARK: Add product API:
    func addProductAPI(){
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["vendor_id" : UserDefaults.standard.value(forKey: "USER_ID") as! String,
                      "product_name" : self.txtProductName.text!,
                      "product_description": self.txtViewDescription.text!,
                      "category":self.selectedId,
                      "maximum_retail_Price":self.txtMaxRetailPrice.text!,
                      "discounted_price": self.txtDiscPrice.text!,
                      "discount_percent": self.txtTotalDiscPrice.text!,
                      "quantity": self.txtQuantity.text!,
                      "minquantity":txtMinOrderQuantity.text!,
                      "company_name":txtCompanyName.text!]
        
        uploadImage(urlString: baseUrl + APIEndPoint.userCase.addProduct.caseValue, params: params, imageKeyValue: "image", image: productImage, success: { (response) in
            let dict:NSDictionary = response
            print(dict)
            if dict.value(forKeyPath: "status") as! String == "0"{
                self.hideProgress()
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dict.value(forKey: "message") as! String, viewController: self)
            }else {
                self.hideProgress()
                self.stopAnim()
                
                let refreshAlert = UIAlertController(title: "Message", message:dict.value(forKey: "message") as! String, preferredStyle: UIAlertController.Style.alert)
                
                refreshAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action: UIAlertAction!) in
                    print("Handle Ok logic here")
                   self.popSague()
                }))
                
                self.present(refreshAlert, animated: true, completion: nil)
            }
        }) { (error) in
            self.hideProgress()
            print(error)
        }
     
    }
    func popSague(){
        self.navigationController?.popViewController(animated: true)
    }
}
