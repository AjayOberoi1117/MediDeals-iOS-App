//
//  OrderPlacedViewController.swift
//  MediDeals
//
//  Created by Pankaj Rana on 15/06/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class OrderPlacedViewController: UIViewController {
    @IBOutlet weak var searchView: UIView!
    @IBOutlet weak var TableViewTopConstraints: NSLayoutConstraint!
    @IBOutlet weak var searchProductTxt: UISearchBar!
    @IBOutlet var tableViewData: UITableView!
    @IBOutlet weak var searchBtn: UIButton!
    @IBOutlet var noDataImage: UIImageView!
    var search_text:String!
    var isSearchActive: Bool = false
    var isSearch = "no"
    private var CellExpanded: Bool = false
    private var CellSelected = Int()
    
    var getAllResponseData = [getOrderPlaced]()
    var pageno = Int()
    var totalPage = Int()
    var getAllDataArr = NSArray()
    var filteredArr = NSMutableArray()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        TableViewTopConstraints.constant = 0
        // Do any additional setup after loading the view.
        showAllPlacedOrderAPI()
    }
    
    @IBAction func searchBtn(_ sender: Any) {
        if isSearch == "no"{
            UIView.animate(withDuration: 0.3, delay: 0, options: UIView.AnimationOptions.curveEaseIn, animations: {
                self.searchView.isHidden = false
                self.TableViewTopConstraints.constant = 50
                self.isSearch = "yes"
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
    
    @IBAction func EditOrder(_ sender: DesignableButton) {
        let controller = UIAlertController(title: "Choose a Order Status", message: nil, preferredStyle: UIAlertController.Style.actionSheet)
        controller.view.tintColor = UIColor.black
        let closure = { (action: UIAlertAction!) -> Void in
            let index = controller.actions.firstIndex(of: action)
            if index != nil {
                NSLog("Index: \(index!)")
                print(PlacedOrderStatusTitle[index!])
                // let selected_type = orderStatusTitle[index!]
                //                self.txtAccountType.text = selected_type
            }
        }
        for i in 0 ..< PlacedOrderStatusTitle.count { controller.addAction(UIAlertAction(title: PlacedOrderStatusTitle[i], style: .default, handler: closure))
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
    
    
    func showAllPlacedOrderAPI(){
        self.addLoadingIndicator()
        self.startAnim()
        //UserDefaults.standard.value(forKey: "USER_ID") as! String
        let params = [ "vendor_id" : "26",
                       "page_no" : "\(pageno)"]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.orderPlaced.caseValue,parameters: params){ (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                self.getAllResponseData = [getOrderPlaced]()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
                self.tableViewData.reloadData()
            } else {
                self.stopAnim()
                self.totalPage = (dic.value(forKey: "totalpage") as! NSString).integerValue
                if let data = (dic.value(forKey: "result") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    self.getAllResponseData = [getOrderPlaced]()
                    if data.count == 0{
                        self.stopAnim()
                        Utilities.ShowAlertView2(title: "Alert", message: "No Records Found!", viewController: self)
                        self.tableViewData.reloadData()
                    }else{
                        self.getAllDataArr = NSArray()
                        self.getAllDataArr = data
                        
                        for index in 0..<data.count
                        {
                            self.getAllResponseData.append(getOrderPlaced(order_id: "\((data[index] as AnyObject).value(forKey: "order_id") ?? "")", date: "\((data[index] as AnyObject).value(forKey: "date") ?? "")", phone: "\((data[index] as AnyObject).value(forKey: "phone") ?? "")", total_amount: "\((data[index] as AnyObject).value(forKey: "total_amount") ?? "")", money_status: "\((data[index] as AnyObject).value(forKey: "money_status") ?? "")", details: ((data[index] as AnyObject).value(forKey: "details") as! NSDictionary)))
                        }
                        self.tableViewData.reloadData()
                    }
                }
            }
        }
    }
}
@available(iOS 11.0, *)
extension OrderPlacedViewController : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        return self.getAllResponseData.count
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as? orderPlacedCell{
            cell.dropDownBtn.tag = indexPath.row
           
                cell.invoiceNo.text =  "Order No: " + getAllResponseData[indexPath.row].order_id
                cell.orderDate.text =  "Order Date: " + getAllResponseData[indexPath.row].date
                cell.customerName.text =  "Customer Number: " + getAllResponseData[indexPath.row].phone
                cell.totalAmount.text =  "Total Amount: " + getAllResponseData[indexPath.row].total_amount
                cell.moneyStatus.text =  "Money Status: " + getAllResponseData[indexPath.row].money_status
                
                cell.billTo.text = "Bill To: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "billTo") as! String)"
                cell.address.text = "Address: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "bill_address") as! String)"
                cell.shipTo.text = "Ship To: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "shipTo") as! String)"
                cell.shipAddress.text = "Address: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "shipaddress") as! String)"
                cell.email.text = "Email: " + "\(getAllResponseData[indexPath.row].details.value(forKey: "email") as! String)"
                
                
                let arr = getAllResponseData[indexPath.row].details.value(forKey: "productDetails") as! NSArray
                
                cell.productName.text =
                    "Product Name: " + "\((arr[0] as AnyObject).value(forKey: "product_name") as! String)"
                    + "\n" +
                    "Price per Item: " + "\((arr[0] as AnyObject).value(forKey: "per_price") as! NSNumber)"
                    + "\n" +
                    "Quantity: " + "\((arr[0] as AnyObject).value(forKey: "quantity") as! String)"
                    + "\n" +
                    "Company: " + "\((arr[0] as AnyObject).value(forKey: "company") as! String)"
                    + "\n" +
                    "Total Amount: " + "\((arr[0] as AnyObject).value(forKey: "total_price") as! String)"
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
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if CellSelected == indexPath.row{
            if CellExpanded {
                return 530
            } else {
                return 200
            }
        }else{
            return 200
        }
        
    }
}
class orderPlacedCell:UITableViewCell{
    @IBOutlet weak var dropDownBtn: DesignableButton!
    @IBOutlet weak var invoiceNo: UILabel!
    @IBOutlet weak var orderDate: UILabel!
    @IBOutlet weak var customerName: UILabel!
    @IBOutlet weak var totalAmount: UILabel!
    @IBOutlet weak var moneyStatus: UILabel!
    
    
    @IBOutlet weak var billTo: UILabel!
    @IBOutlet weak var address: UILabel!
    @IBOutlet weak var shipTo: UILabel!
    @IBOutlet weak var shipAddress: UILabel!
    @IBOutlet weak var email: UILabel!
    @IBOutlet weak var productDetail: UILabel!
    @IBOutlet weak var productName: UILabel!
}
