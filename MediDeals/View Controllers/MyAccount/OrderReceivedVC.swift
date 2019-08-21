//
//  OrderReceivedVC.swift
//  MediDeals
//
//  Created by Pankaj Rana on 15/06/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class OrderReceivedVC: UIViewController,UITextViewDelegate{
    @IBOutlet weak var searchView: UIView!
    @IBOutlet weak var TableViewTopConstraints: NSLayoutConstraint!
    @IBOutlet weak var searchProductTxt: UISearchBar!
    @IBOutlet var tableViewData: UITableView!
    @IBOutlet weak var searchBtn: UIButton!
    @IBOutlet var noDataImage: UIImageView!
    
    @IBOutlet weak var hiddenView: UIView!
    @IBOutlet weak var docketView: DesignableView!
    @IBOutlet weak var DocketTextView: UITextView!
    
    var selectedProduct = ""
    var selectedOrderStatus = ""
    var search_text:String!
    var isSearchActive: Bool = false
    var isSearch = "no"
    private var CellExpanded: Bool = false
    private var CellSelected = Int()
    var getAllResponseData = [getOrderReceived]()
    var pageno = Int()
    var totalPage = Int()
    var getAllDataArr = NSArray()
    var filteredArr = NSMutableArray()
    override func viewDidLoad() {
        super.viewDidLoad()
        TableViewTopConstraints.constant = 0
        // Do any additional setup after loading the view.
        DocketTextView.delegate = self
        DocketTextView.text = "Enter description ..."
        self.docketView.isHidden = true
        self.hiddenView.isHidden = true
        self.hiddenView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTappedOnView)))
        showAllRecivedOrderAPI()
    }
    @objc func didTappedOnView(){
        self.docketView.isHidden = true
        self.hiddenView.isHidden = true
    }
    
    //MARK:- UITextViewDelegates
    func textViewDidBeginEditing(_ textView: UITextView) {
        if DocketTextView.text == "Enter description ..." {
            DocketTextView.text = ""
            DocketTextView.textColor = UIColor.black
        }
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
        }
        return true
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if DocketTextView.text == "" {
            DocketTextView.text = "Enter description ..."
            DocketTextView.textColor = UIColor.lightGray
        }
    }
    
    @IBAction func searchBtn(_ sender: Any) {
        if isSearch == "no"{
            UIView.animate(withDuration: 0.3, delay: 0, options: UIView.AnimationOptions.curveEaseIn, animations: {
                self.searchView.isHidden = false
                self.TableViewTopConstraints.constant = 50
                self.isSearch = "yes"
                self.pageno = 1
                self.view.layoutIfNeeded()
                
            }, completion: nil)
            
        }else{
            UIView.animate(withDuration: 0.3, delay: 0, options: UIView.AnimationOptions.curveEaseOut, animations: {
                self.searchView.isHidden = true
                self.TableViewTopConstraints.constant = 0
                self.isSearch = "no"
                self.view.layoutIfNeeded()
                
            }, completion: nil)
            
        }
    }
    @IBAction func editDocketNumber(_ sender: DesignableButton) {
        let tagValue = sender.tag
        self.selectedProduct = getAllResponseData[tagValue].list_id
        self.docketView.isHidden = false
        self.hiddenView.isHidden = false
    }
    @IBAction func EditOrder(_ sender: DesignableButton) {
        let tagValue = sender.tag
        self.selectedProduct = getAllResponseData[tagValue].list_id
        
        let controller = UIAlertController(title: "Choose a Order Status", message: nil, preferredStyle: UIAlertController.Style.actionSheet)
        controller.view.tintColor = UIColor.black
        let closure = { (action: UIAlertAction!) -> Void in
            let index = controller.actions.firstIndex(of: action)
            if index != nil {
                NSLog("Index: \(index!)")
                print(orderStatusTitle[index!])
               self.selectedOrderStatus = orderStatusTitleID[index!]
                self.editOrderStatusAPI()
            }
        }
        for i in 0 ..< orderStatusTitle.count { controller.addAction(UIAlertAction(title: orderStatusTitle[i], style: .default, handler: closure))
            // selected_Year = self.yearsArr[i] as? String
            
        }
        controller.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel, handler: nil))
        present(controller, animated: true, completion: nil)
    }
    @IBAction func dropDownAct(_ sender: UIButton) {
        var superview = sender.superview
        while let view = superview, !(view is UITableViewCell) {
            superview = view.superview
        }
        guard let cell = superview as? UITableViewCell else {
            print("button is not contained in a table view cell")
            return
        }
        guard let indexPath = tableViewData.indexPath(for: cell) else {
            print("failed to get index path for cell containing button")
            return
        }
        // We've got the index path for the cell that contains the button, now do something with it.
        print("button is in row \(indexPath.row)")
        
        CellSelected = sender.tag
        if CellExpanded {
            CellExpanded = false
        } else {
            CellExpanded = true
        }
        tableViewData.beginUpdates()
        tableViewData.endUpdates()
        tableViewData.reloadRows(at: [indexPath], with: .automatic)
    }
    
    @IBAction func docketSubmit(_ sender: DesignableButton) {
        if DocketTextView.text == "Enter description ..." || DocketTextView.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter Shipping Details & Docket No. ", viewController: self)
        }else{
            self.editDocketNoAPI()
        }
    }
    
    
    //Show All Product API
func showAllRecivedOrderAPI(){
        self.addLoadingIndicator()
        self.startAnim()
        //UserDefaults.standard.value(forKey: "USER_ID") as! String
        let params = [ "vendor_id" : "26",
                       "page_no" : "\(pageno)"]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.orderReceived.caseValue,parameters: params){ (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                self.getAllResponseData = [getOrderReceived]()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
                self.tableViewData.reloadData()
            } else {
                self.stopAnim()
                self.totalPage = (dic.value(forKey: "totalpage") as! NSString).integerValue
                if let data = (dic.value(forKey: "result") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    self.getAllResponseData = [getOrderReceived]()
                    if data.count == 0{
                        self.stopAnim()
                        Utilities.ShowAlertView2(title: "Alert", message: "No Records Found!", viewController: self)
                        self.tableViewData.reloadData()
                    }else{
                        self.getAllDataArr = NSArray()
                        self.getAllDataArr = data
                        
                        for index in 0..<data.count
                        {
                            self.getAllResponseData.append(getOrderReceived(list_id: "\((data[index] as AnyObject).value(forKey: "list_id") ?? "")", order_id: "\((data[index] as AnyObject).value(forKey: "order_id") ?? "")", date: "\((data[index] as AnyObject).value(forKey: "date") ?? "")", customer_number: "\((data[index] as AnyObject).value(forKey: "customer_number") ?? "")", order_status: "\((data[index] as AnyObject).value(forKey: "order_status") ?? "")", docket_number: "\((data[index] as AnyObject).value(forKey: "docket_number") ?? "")", money_status: "\((data[index] as AnyObject).value(forKey: "money_status") ?? "")", details: ((data[index] as AnyObject).value(forKey: "details") as! NSDictionary)))
                        }
                        self.tableViewData.reloadData()
                    }
                }
            }
        }
    }
  func editOrderStatusAPI(){
        self.addLoadingIndicator()
        self.startAnim()
        let params = [ "list_id" : self.selectedProduct,
                       "orders_status" : self.selectedOrderStatus]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.changeOrderStatus.caseValue,parameters: params){ (response) in
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
            }
              
        }
    }
    func editDocketNoAPI(){
        self.addLoadingIndicator()
        self.startAnim()
        let params = [ "list_id" : self.selectedProduct,
                       "docket_number" : self.DocketTextView.text!]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.addEditDocketNumber.caseValue,parameters: params){ (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            } else {
                self.stopAnim()
                self.docketView.isHidden = true
                self.hiddenView.isHidden = true
                DocketTextView.text = "Enter description ..."
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            }
            
        }
    }
}
@available(iOS 11.0, *)
extension OrderReceivedVC : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        return self.getAllResponseData.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as? orderRecivedCell{
            cell.dropDownBtn.tag = indexPath.row
            cell.editBtn.tag = indexPath.row
            cell.editDocket.tag = indexPath.row
            cell.orderNo.text = "Order Number: " + getAllResponseData[indexPath.row].order_id
            cell.orderDate.text = "Order Date: " + getAllResponseData[indexPath.row].date
            cell.customerName.text = "Customer Number: " + getAllResponseData[indexPath.row].customer_number
            cell.orderStatus.text = "Order Status: " + getAllResponseData[indexPath.row].order_status
            cell.docketNo.text = "Docket Number: " + getAllResponseData[indexPath.row].docket_number
            cell.moneyStatus.text = "Money Status: " + getAllResponseData[indexPath.row].money_status
            
            cell.billTo.text = "Bill To: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "billTo") as! String)"
            cell.address.text = "Address: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "bill_address") as! String)"
            cell.shipTo.text = "Ship To: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "shipTo") as! String)"
            cell.shipAddress.text = "Address: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "shipaddress") as! String)"
            cell.email.text = "Email: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "email") as! String)"
            cell.productDetail.text = "Product Details: " + "\n" +
                "Product Name: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "product_name") as! String)"
            + "\n" +
                "Price per Item: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "per_price") as! NSNumber)"
                + "\n" +
                "Quantity: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "quantity") as! String)"
                + "\n" +
                "Company: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "company") as! String)"
                + "\n" +
                "Total Amount: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "total_price") as! String)"
            
            if CellSelected == indexPath.row{
                if CellExpanded {
                    cell.dropDownBtn.setImage(UIImage(named: "up-arrow"), for: .normal)
                }else{
                     cell.dropDownBtn.setImage(UIImage(named: "down-arrow"), for: .normal)
                }
            }else{
                cell.dropDownBtn.setImage(UIImage(named: "down-arrow"), for: .normal)
            }
            return cell
        }
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            if CellSelected == indexPath.row{
                if CellExpanded {
                    return 520
                } else {
                    return 270
                }
            }else{
                return 270
            }
        
    }
// 500 - 260
}
class orderRecivedCell:UITableViewCell{
    @IBOutlet weak var orderNo: UILabel!
    @IBOutlet weak var orderDate: UILabel!
    @IBOutlet weak var customerName: UILabel!
    @IBOutlet weak var orderStatus: UILabel!
    @IBOutlet weak var docketNo: UILabel!
    @IBOutlet weak var moneyStatus: UILabel!
    
    @IBOutlet weak var dropDownBtn: DesignableButton!
    @IBOutlet weak var editBtn: DesignableButton!
    @IBOutlet weak var editDocket: DesignableButton!
    
    @IBOutlet weak var billTo: UILabel!
    @IBOutlet weak var address: UILabel!
    @IBOutlet weak var shipTo: UILabel!
    @IBOutlet weak var shipAddress: UILabel!
    @IBOutlet weak var email: UILabel!
    @IBOutlet weak var productDetail: UILabel!
    @IBOutlet weak var productName: UILabel!
    
}
