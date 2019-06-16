//
//  OrderReceivedVC.swift
//  MediDeals
//
//  Created by Pankaj Rana on 15/06/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class OrderReceivedVC: UIViewController {
    @IBOutlet weak var searchView: UIView!
    @IBOutlet weak var TableViewTopConstraints: NSLayoutConstraint!
    @IBOutlet weak var searchProductTxt: UISearchBar!
    @IBOutlet var tableViewData: UITableView!
    @IBOutlet weak var searchBtn: UIButton!
    @IBOutlet var noDataImage: UIImageView!
    
    var search_text:String!
    var isSearchActive: Bool = false
    var isSearch = "no"
    override func viewDidLoad() {
        super.viewDidLoad()
        TableViewTopConstraints.constant = 0
        // Do any additional setup after loading the view.
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
        let controller = UIAlertController(title: "Choose a Order Status", message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        controller.view.tintColor = UIColor.black
        let closure = { (action: UIAlertAction!) -> Void in
            let index = controller.actions.index(of: action)
            if index != nil {
                NSLog("Index: \(index!)")
                print(orderStatusTitle[index!])
                let selected_type = orderStatusTitle[index!]
//                self.txtAccountType.text = selected_type
            }
        }
        for i in 0 ..< orderStatusTitle.count { controller.addAction(UIAlertAction(title: orderStatusTitle[i], style: .default, handler: closure))
            // selected_Year = self.yearsArr[i] as? String
            
        }
        controller.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: nil))
        present(controller, animated: true, completion: nil)
    }
}
@available(iOS 11.0, *)
extension OrderReceivedVC : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{ return 10
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as? orderRecivedCell{
            
            return cell
        }
        return UITableViewCell()
    }
}
class orderRecivedCell:UITableViewCell{
    
}
