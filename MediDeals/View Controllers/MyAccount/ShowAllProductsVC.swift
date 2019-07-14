//
//  ShowAllProductsVC.swift
//  MediDeals
//
//  Created by Pankaj Rana on 09/06/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
import CRRefresh
@available(iOS 11.0, *)

class ShowAllProductsVC: UIViewController,UISearchBarDelegate,UIScrollViewDelegate {
    @IBOutlet weak var searchView: UIView!
    @IBOutlet weak var TableViewTopConstraints: NSLayoutConstraint!
    @IBOutlet weak var searchProductTxt: UISearchBar!
    @IBOutlet var tableViewData: UITableView!
    @IBOutlet weak var searchBtn: UIButton!
    @IBOutlet var noDataImage: UIImageView!
    var getAllResponseData = [getAllResponse]()
    var search_text:String!
    var isSearchActive: Bool = false
    var isSearch = "no"
    var pageno = Int()
    var totalPage = Int()
    var getAllDataArr = NSArray()
    var filteredArr = NSMutableArray()
    override func viewDidLoad() {
        super.viewDidLoad()
        searchProductTxt.delegate = self
        searchView.isHidden = true
        pageno = 1
        TableViewTopConstraints.constant = 0
        // Do any additional setup after loading the view.
        showAllProductAPI()
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
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if ((tableViewData.contentOffset.y + tableViewData.frame.size.height) >= tableViewData.contentSize.height)
        {
            pageno = pageno+1
            if totalPage >= pageno{
                self.showAllProductAPI()
            }
            
            tableViewData.cr.addFootRefresh(animator: NormalFooterAnimator()) { [weak self] in
                /// start refresh
                /// Do anything you want...
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                    /// Stop refresh when your job finished, it will reset refresh footer if completion is true
                    
                })
            }
        }
    }
    
    
    
    //MARK: ...FOR SEARCH BAR DELEGATE...
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchProductTxt.endEditing(true)
        
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.count == 0 {
            isSearchActive = false
            searchProductTxt.resignFirstResponder()
            filteredArr = NSMutableArray()
           self.showAllProductAPI()
        }else{
            self.textMatch(textTyped: searchText)
        }
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        //        searchBar_out.tintColor = UIColor.white
        searchProductTxt.showsCancelButton = true
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchProductTxt.showsCancelButton = false
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchProductTxt.endEditing(true)
        if searchProductTxt.text!.count != 0 {
            isSearchActive = false
//            filteredArr = NSMutableArray()
//            self.CallFn()
            
        }
    }
    func textMatch(textTyped: String) {
        if textTyped != "" {
            isSearchActive = true
            filteredArr.removeAllObjects()
            let predicate2 = NSPredicate(format: "product_name BEGINSWITH[c] %@", textTyped)
            filteredArr = NSMutableArray(array: self.getAllDataArr.filtered(using: predicate2))

            print("new array is ++++++\(filteredArr)")

            self.getAllResponseData = [getAllResponse]()
            for index in 0..<filteredArr.count
            {
                 self.getAllResponseData.append(getAllResponse(product_id: "\((filteredArr[index] as AnyObject).value(forKey: "product_id") ?? "")", description: "\((filteredArr[index] as AnyObject).value(forKey: "description") ?? "")", mrp: "\((filteredArr[index] as AnyObject).value(forKey: "mrp") ?? "")", new_price: "\((filteredArr[index] as AnyObject).value(forKey: "new_price") ?? "")", product_name: "\((filteredArr[index] as AnyObject).value(forKey: "product_name") ?? "")", quantity: "\((filteredArr[index] as AnyObject).value(forKey: "quantity") ?? "")", image: "\((filteredArr[index] as AnyObject).value(forKey: "image") ?? "")"))

            }
            
            self.stopAnim()
            self.tableViewData.reloadData()
        }
        else {
            isSearchActive = false
            searchProductTxt.endEditing(true)
        }

    }
    
    
    //Show All Product API
    
    func showAllProductAPI(){
        self.addLoadingIndicator()
        self.startAnim()
        
        let params = [ "vendor_id" : UserDefaults.standard.value(forKey: "USER_ID") as! String,
                       "page_no" : "\(pageno)",
                       "search": ""]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.showAllProduct.caseValue,parameters: params){ (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            } else {
                self.stopAnim()
                 self.totalPage = (dic.value(forKey: "totalpage") as! NSString).integerValue
                if let data = (dic.value(forKey: "result") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    if data.count == 0{
                        self.stopAnim()
                        Utilities.ShowAlertView2(title: "Alert", message: "No Records Found!", viewController: self)
                    }else{
                        self.getAllDataArr = NSArray()
                        self.getAllDataArr = data
                        self.getAllResponseData = [getAllResponse]()
                        for index in 0..<data.count
                        {
                            self.getAllResponseData.append(getAllResponse(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", description: "\((data[index] as AnyObject).value(forKey: "description") ?? "")", mrp: "\((data[index] as AnyObject).value(forKey: "mrp") ?? "")", new_price: "\((data[index] as AnyObject).value(forKey: "new_price") ?? "")", product_name: "\((data[index] as AnyObject).value(forKey: "product_name") ?? "")", quantity: "\((data[index] as AnyObject).value(forKey: "quantity") ?? "")", image: "\((data[index] as AnyObject).value(forKey: "image") ?? "")"))
                        }
                        self.tableViewData.reloadData()
                    }
                }
            }
        }
    }

    @IBAction func edit(_ sender: DesignableButton) {
        
    }
    
    @IBAction func addLocation(_ sender: DesignableButton) {
        
    }
    
    @IBAction func DeleteAct(_ sender: DesignableButton) {
        
    }
    @IBAction func viewLocation(_ sender: DesignableButton) {
        
    }
}
@available(iOS 11.0, *)
extension ShowAllProductsVC : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        
        if self.getAllResponseData.count != 0{ return self.getAllResponseData.count }
        else{ return 0 }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as? productsCell{
            cell.titleName.text = self.getAllResponseData[indexPath.row].product_name
            cell.desc.text = self.getAllResponseData[indexPath.row].description.html2String
            cell.mrp.text = "MRP: " + self.getAllResponseData[indexPath.row].mrp
            cell.quantity.text = "Quantity: " + self.getAllResponseData[indexPath.row].quantity
            cell.newPrice.text = "New Price: " + self.getAllResponseData[indexPath.row].new_price
            cell.delete.tag = indexPath.row
            cell.addLocation.tag = indexPath.row
            cell.viewLocation.tag = indexPath.row
            cell.edit.tag = indexPath.row
            return cell
        }
    return UITableViewCell()
}
}
class productsCell:UITableViewCell{
    @IBOutlet weak var titleName: UILabel!
    @IBOutlet weak var desc: UILabel!
    @IBOutlet weak var quantity: UILabel!
    @IBOutlet weak var mrp: UILabel!
    @IBOutlet weak var newPrice: UILabel!
    @IBOutlet weak var edit: DesignableButton!
    @IBOutlet weak var addLocation: DesignableButton!
    @IBOutlet weak var viewLocation: DesignableButton!
    @IBOutlet weak var delete: DesignableButton!
    
}
