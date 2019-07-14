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
        let controller = UIAlertController(title: "Choose a Order Status", message: nil, preferredStyle: UIAlertController.Style.actionSheet)
        controller.view.tintColor = UIColor.black
        let closure = { (action: UIAlertAction!) -> Void in
            let index = controller.actions.index(of: action)
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
}
@available(iOS 11.0, *)
extension OrderPlacedViewController : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        return 10
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as? orderPlacedCell{
            cell.dropDownBtn.tag = indexPath.row
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
    @IBOutlet weak var dropDownBtn: DesignableButton!}
