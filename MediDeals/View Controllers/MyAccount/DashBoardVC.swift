//
//  DashBoardVC.swift
//  MediDeals
//
//  Created by Apple on 05/06/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class DashBoardVC: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    
    var titleArry = ["Selling Details", "Buying Details"]
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 200
        // Do any additional setup after loading the view.
    }
    

   
}
@available(iOS 11.0, *)
extension DashBoardVC : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        return titleArry.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let tableCell = tableView.dequeueReusableCell(withIdentifier: "tableCell", for: indexPath) as? DashBoardTableCell {
        tableCell.namelbl.text = titleArry[indexPath.row]
        tableCell.collectionView.tag = indexPath.row
        return tableCell
            
        }
        return UITableViewCell()
    
        
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.row == 0 {
            return 550
        }else{
            return 550
        }
    }
    
    //    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    //        let vc = self.storyboard?.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
    //        self.navigationController?.pushViewController(vc, animated: true)
    //    }
    
}
@available(iOS 11.0, *)
extension DashBoardVC : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
       if collectionView.tag == 0{
        return DashBoardSellingName.count
        }else{
           return DashBoardBuyingName.count
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "collectionCell", for: indexPath as IndexPath) as? DashBoardCollectionViewCell
        {
            if collectionView.tag == 0{
                cell.menuView.backgroundColor = colorArray10[indexPath.row]
                cell.titleName.text = DashBoardSellingName[indexPath.row]
                cell.MenuImage.image = DashBoardSellingImages[indexPath.row]
            }else{
                cell.menuView.backgroundColor = colorArray8[indexPath.row]
                cell.titleName.text = DashBoardBuyingName[indexPath.row]
                cell.MenuImage.image = DashBoardBuyingImages[indexPath.row]
            }
            return cell
        }
        return UICollectionViewCell()
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        //        let vc = self.storyboard?.instantiateViewController(withIdentifier: "ChooseCategoryVC") as! ChooseCategoryVC
        //        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width:(collectionView.frame.width)/3-10, height: 120)
    }
    
    
}

class DashBoardTableCell:UITableViewCell{
    @IBOutlet weak var namelbl: UILabel!
    @IBOutlet weak var collectionView: UICollectionView!
    
}

class DashBoardCollectionViewCell: UICollectionViewCell {
    @IBOutlet weak var MenuImage: UIImageView!
    @IBOutlet weak var titleName: UILabel!
    @IBOutlet var menuView: DesignableView!
    
}
