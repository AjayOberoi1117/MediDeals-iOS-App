//
//  ShowResponsesViewController.swift
//  MediDeals
//
//  Created by Pankaj Rana on 15/06/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class ShowResponsesViewController: UIViewController {
    @IBOutlet weak var searchView: UIView!
    @IBOutlet weak var TableViewTopConstraints: NSLayoutConstraint!
    @IBOutlet weak var searchProductTxt: UISearchBar!
    @IBOutlet var tableViewData: UITableView!
    @IBOutlet weak var searchBtn: UIButton!
    var getResponse = [getAllEnquire]()
    var search_text:String!
    var isSearchActive: Bool = false
    var isSearch = "no"
    override func viewDidLoad() {
        super.viewDidLoad()
        TableViewTopConstraints.constant = 0
        // Do any additional setup after loading the view.
        showAllResponsedAPI()
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
    
    func showAllResponsedAPI(){
        self.addLoadingIndicator()
        self.startAnim()
        
        let params = [ "vendor_id" : "26"]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.getEnquirie.caseValue,parameters: params){ (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
                self.tableViewData.reloadData()
            } else {
                self.stopAnim()
                self.getResponse = [getAllEnquire]()
                if let data = (dic.value(forKey: "message") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    if data.count == 0{
                        self.stopAnim()
                        Utilities.ShowAlertView2(title: "Alert", message: "No Records Found!", viewController: self)
                        self.tableViewData.reloadData()
                    }else{
                        
                        for index in 0..<data.count
                        {
                            self.getResponse.append(getAllEnquire(response_id: "\((data[index] as AnyObject).value(forKey: "response_id") ?? "")", vendor_id: "\((data[index] as AnyObject).value(forKey: "vendor_id") ?? "")", vendor_email: "\((data[index] as AnyObject).value(forKey: "vendor_email") ?? "")", message: "\((data[index] as AnyObject).value(forKey: "message") ?? "")", date: "\((data[index] as AnyObject).value(forKey: "date") ?? "")"))
                        }
                        self.tableViewData.reloadData()
                    }
                }
            }
        }
    }

}
@available(iOS 11.0, *)
extension ShowResponsesViewController : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        return self.getResponse.count
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as? responsesCell{
            cell.responseID.text = "Response Id: " + self.getResponse[indexPath.row].response_id
            cell.venderID.text = "Vender Id: " + self.getResponse[indexPath.row].vendor_id
            cell.venerEmail.text = "Vender Email: " + self.getResponse[indexPath.row].vendor_email
            cell.message.text = "Message: " + self.getResponse[indexPath.row].message
            cell.date.text = "Date: " + self.getResponse[indexPath.row].date
            return cell
        }
        return UITableViewCell()
    }
}
class responsesCell:UITableViewCell{
    @IBOutlet weak var responseID: UILabel!
    @IBOutlet weak var venderID: UILabel!
    @IBOutlet weak var venerEmail: UILabel!
    @IBOutlet weak var message: UILabel!
    @IBOutlet weak var date: UILabel!
    
}
