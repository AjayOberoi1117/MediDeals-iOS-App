//
//  MyAccountViewController.swift
//  MediDeals
//
//  Created by SIERRA on 1/7/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class MyAccountViewController: UIViewController {
    @IBOutlet weak var tableView: UITableView!
    
    var titleArry = ["Seller Zone", "Buyer Zone"]
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        tableView.rowHeight = UITableViewAutomaticDimension
        self.tableView.estimatedRowHeight = 200
        
//        self.addLoadingIndicator()
//         self.startAnim()
    }
    override func viewWillAppear(_ animated: Bool) {
        Utilities.AttachSideMenuController()
        Utilities.HideRightSideMenu()
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    @IBAction func menuAct(_ sender: UIBarButtonItem) {
        Utilities.LeftSideMenu()
    }
 
}
@available(iOS 11.0, *)
extension MyAccountViewController : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        return titleArry.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let tableCell = tableView.dequeueReusableCell(withIdentifier: "tableCell", for: indexPath) as? MyAccountTableCell {
            tableCell.namelbl.text = titleArry[indexPath.row]
            tableCell.collectionView.tag = indexPath.row
            return tableCell
            
        }
        return UITableViewCell()
        
        
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.row == 0 {
            return 300
        }else{
            return 200
        }
    }

    
}
@available(iOS 11.0, *)
extension MyAccountViewController : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView.tag == 0{
            return SellerTitleName.count
        }else{
            return BuyerTitleName.count
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "collectionCell", for: indexPath as IndexPath) as? AccountCollectionViewCell
        {
            if collectionView.tag == 0{
                cell.menuView.backgroundColor = colorArraySeller[indexPath.row]
                cell.titleName.text = SellerTitleName[indexPath.row]
                cell.MenuImage.image = SellerTitleImages[indexPath.row]
            }else{
                cell.menuView.backgroundColor = colorArrayBuyer[indexPath.row]
                cell.titleName.text = BuyerTitleName[indexPath.row]
                cell.MenuImage.image = BuyerTitleImages[indexPath.row]
            }
            return cell
        }
        return UICollectionViewCell()
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView.tag == 0{
            if indexPath.row == 0 {
                performPushSeguefromController(identifier: "DashBoardVC")
            }else if indexPath.row == 1 {
                performPushSeguefromController(identifier: "AddProductsVC")
            }else if indexPath.row == 2 {
                performPushSeguefromController(identifier: "ShowAllProductsVC")
            }else if indexPath.row == 3 {
                performPushSeguefromController(identifier: "SubscriptionViewController")
            }else if indexPath.row == 4 {
                performPushSeguefromController(identifier: "OrderReceivedVC")
            }else if indexPath.row == 5 {
                performPushSeguefromController(identifier: "BankDetailsVC")
            }else if indexPath.row == 6 {
                performPushSeguefromController(identifier: "AddProductsVC")
            }
        }else{
            if indexPath.row == 0 {
                performPushSeguefromController(identifier: "OrderPlacedViewController")
            }else if indexPath.row == 1 {
                performPushSeguefromController(identifier: "EnquiryViewController")
            }else if indexPath.row == 2 {
               // performPushSeguefromController(identifier: "")
            }
        }
    }
 
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width:(collectionView.frame.width)/3-10, height: 120)
    }
    
    
}
class MyAccountTableCell:UITableViewCell{
    @IBOutlet weak var namelbl: UILabel!
    @IBOutlet weak var collectionView: UICollectionView!
    
}
