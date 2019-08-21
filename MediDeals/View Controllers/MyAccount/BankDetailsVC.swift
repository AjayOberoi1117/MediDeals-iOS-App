//
//  BankDetailsVC.swift
//  MediDeals
//
//  Created by Pankaj Rana on 08/06/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

protocol TheDelegate: class {
    func didScroll(to position: CGFloat)
}

@available(iOS 11.0, *)
class BankDetailsVC: UIViewController, TheDelegate {
    func didScroll(to position: CGFloat) {
        for cell in BankDetailTableView.visibleCells as! [BankDetailsTableCell] {
            (cell.detailCollectionView as UIScrollView).contentOffset.x = position
        }
    }
    var datePicker = UIDatePicker()
    var cell = BankDetailsTableCell()
    var Action = ""
    var pageno = Int()
    var totalPage = Int()
    var getAllDataArr = NSArray()
    var filteredArr = NSMutableArray()
    var getAllResponseData = [getBankDetails]()
    var detailArray: [[String]] = []
    var detailArray1: [String] = []
    @IBOutlet weak var BankDetailTableView: UITableView!
    @IBOutlet weak var hiddenView: UIView!
    @IBOutlet weak var AddDetailsView: UIView!
    
    @IBOutlet weak var bankName: DesignableTextField!
    @IBOutlet weak var bankAccountNumber: DesignableTextField!
    @IBOutlet weak var ifcsCode: DesignableTextField!
    @IBOutlet weak var bankAddress: DesignableTextField!
    @IBOutlet weak var phnNumber: DesignableTextField!
    @IBOutlet weak var upiNumber: DesignableTextField!
    @IBOutlet weak var enterDate: DesignableTextField!
    
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideLeftSideMenu()
        Utilities.HideRightSideMenu()
        self.AddDetailsView.isHidden = true
        self.hiddenView.isHidden = true
        Action = "no"
        // Do any additional setup after loading the view.
         self.hiddenView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTappedOnView)))
        showDatePicker()
       getBankDetail_API()
    }
    @IBAction func AddDetailsBtn(_ sender: UIBarButtonItem) {
        if Action == "no"{
            self.AddDetailsView.isHidden = false
            self.hiddenView.isHidden = false
            Action = "yes"
        }else{
            self.AddDetailsView.isHidden = true
            self.hiddenView.isHidden = true
            Action = "no"
        }
    }
    @objc func didTappedOnView(){
        self.AddDetailsView.isHidden = true
        self.hiddenView.isHidden = true
    }
    @IBAction func ChooseDate(_ sender: UITextField) {
        showDatePicker()
    }
    func showDatePicker(){
        //Formate Date
        datePicker.datePickerMode = .date
        datePicker.maximumDate = Date()
        //ToolBar
        let toolbar = UIToolbar();
        toolbar.sizeToFit()
        let doneButton = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(donedatePicker));
        let spaceButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.flexibleSpace, target: nil, action: nil)
        let cancelButton = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelDatePicker));
        toolbar.tintColor = THEME_COLOR1
        toolbar.setItems([cancelButton,spaceButton,doneButton], animated: false)
        
        enterDate.inputAccessoryView = toolbar
        enterDate.inputView = datePicker
        
    }
    
    @objc func donedatePicker(){
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        enterDate.text = formatter.string(from: datePicker.date)
        self.view.endEditing(true)
    }
    
    @objc func cancelDatePicker(){
        self.view.endEditing(true)
    }
    
    @IBAction func submit(_ sender: DesignableButton) {
        self.validations()
    }
    
    func validations() {
        if self.bankName.text == "" && self.bankAccountNumber.text == "" && self.ifcsCode.text == "" && self.bankAddress.text == "" && self.phnNumber.text == ""  && self.upiNumber.text == "" && self.enterDate.text == ""  {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter all bank information first", viewController: self)
        }
        else if bankName.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter bank name", viewController: self)
        }
        else if bankAccountNumber.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter bank account number", viewController: self)
        }
        else if ifcsCode.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter bank IFCS Code", viewController: self)
        }
        else if bankAddress.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter bank address", viewController: self)
        }
        else if phnNumber.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter phone number", viewController: self)
        }
        else if upiNumber.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter UPI number", viewController: self)
        }
        else if enterDate.text == "" {
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter date", viewController: self)
        }
        else{
            self.addBankDetail_API()
        }
        
    }
    
    
    func getBankDetail_API(){
        self.addLoadingIndicator()
        self.startAnim()
        
        let params = [ "vendor_id" : UserDefaults.standard.value(forKey: "USER_ID") as! String]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.getBankDetail.caseValue,parameters: params){ (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            } else {
                self.stopAnim()
                if let data = (dic.value(forKey: "message") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    if data.count == 0{
                        self.stopAnim()
                        Utilities.ShowAlertView2(title: "Alert", message: "No Records Found!", viewController: self)
                    }else{
                        self.getAllDataArr = NSArray()
                        self.getAllDataArr = data
                        self.getAllResponseData = [getBankDetails]()
                        self.detailArray = [[String]]()
                        for index in 0..<data.count
                        {
                            
                            self.getAllResponseData.append(getBankDetails(id: "\((data[index] as AnyObject).value(forKey: "id") ?? "")",
                                bank_name: "\((data[index] as AnyObject).value(forKey: "bank_name") ?? "")",
                                bank_account: "\((data[index] as AnyObject).value(forKey: "bank_account") ?? "")",
                                ifsc_code: "\((data[index] as AnyObject).value(forKey: "ifsc_code") ?? "")",
                                bank_address: "\((data[index] as AnyObject).value(forKey: "bank_address") ?? "")",
                                phone_number: "\((data[index] as AnyObject).value(forKey: "phone_number") ?? "")",
                                upi_number: "\((data[index] as AnyObject).value(forKey: "upi_number") ?? "")",
                                insert_date: "\((data[index] as AnyObject).value(forKey: "insert_date") ?? "")",
                                firm_name: "\((data[index] as AnyObject).value(forKey: "firm_name") ?? "")",
                                vendor_id: "\((data[index] as AnyObject).value(forKey: "vendor_id") ?? "")"))
                            
                            
                       let a =  [self.getAllResponseData[index].id,
                                 self.getAllResponseData[index].bank_name,
                                 self.getAllResponseData[index].bank_account,
                                 self.getAllResponseData[index].ifsc_code,
                                 self.getAllResponseData[index].bank_address,
                                 self.getAllResponseData[index].phone_number,
                                 self.getAllResponseData[index].upi_number,
                                 self.getAllResponseData[index].insert_date,
                                 self.getAllResponseData[index].firm_name,
                                 self.getAllResponseData[index].vendor_id]
                            
                            self.detailArray.insert(a, at: index)
                        }
                        self.detailArray.insert(["Id","Bank Name","Bank Account","Ifsc Code","Bank Address","Phone Number","Upi Number","Insert Date","Firm Name","Vendor Id"], at: 0)
                        print(self.detailArray)
                        self.BankDetailTableView.reloadData()
                    }
                }
            }
        }
    }
    
    func addBankDetail_API(){
        self.addLoadingIndicator()
        self.startAnim()
        
        let params = [ "vendor_id" : UserDefaults.standard.value(forKey: "USER_ID") as! String,
                       "bank_name" :self.bankName.text!,
                       "bank_account" :self.bankAccountNumber.text!,
                       "ifsc_code" : self.ifcsCode.text!,
                       "bank_address" :self.bankAddress.text!,
                       "phone_number" :self.phnNumber.text!,
                       "upi_number":self.upiNumber.text!,
                       "insert_date": self.enterDate.text!]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.addBankDetail.caseValue,parameters: params){ (response) in
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
                self.bankName.text = ""
                self.bankAccountNumber.text = ""
                self.ifcsCode.text = ""
                self.bankAddress.text = ""
                self.phnNumber.text = ""
                self.upiNumber.text = ""
                self.enterDate.text = ""
                self.AddDetailsView.isHidden = true
                self.hiddenView.isHidden = true
                self.Action = "no"
                self.getBankDetail_API()
            }
        }
    }
}
@available(iOS 11.0, *)
extension BankDetailsVC : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        return detailArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! BankDetailsTableCell
        cell.detailCollectionView.tag = indexPath.row
        //tableCell.detailCollectionView.isPagingEnabled = true
        cell.scrollDelegate = self
//        self.detailArray1 = self.detailArray[indexPath.row]
        cell.detailCollectionView.reloadData()
        return cell
    }
    
}
@available(iOS 11.0, *)
extension BankDetailsVC : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout
{
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            return self.detailArray[collectionView.tag].count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath as IndexPath) as? BankTitleCell
        {
            self.detailArray1 = self.detailArray[collectionView.tag]
            if collectionView.tag == 0{
                cell.name.text = self.detailArray1[indexPath.row]
                cell.name.textColor = UIColor.white
                cell.designView.backgroundColor = THEME_COLOR1
            }else{
                
                cell.name.text = self.detailArray1[indexPath.row]
                cell.name.font = UIFont(name: "Nunito Light", size: 12.0)
            }
            return cell
        }
        return UICollectionViewCell()
    }
    
    
}

extension BankDetailsTableCell: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollDelegate?.didScroll(to: scrollView.contentOffset.x)
    }
}

class BankDetailsTableCell: UITableViewCell{
    @IBOutlet weak var detailCollectionView: UICollectionView!
    weak var scrollDelegate: TheDelegate?
    override func awakeFromNib() {
        super.awakeFromNib()
        (detailCollectionView as UIScrollView).delegate = self
        
    }
}
class BankTitleCell:UICollectionViewCell{
    @IBOutlet weak var name: UILabel!
    @IBOutlet weak var designView: DesignableView!
    
}
