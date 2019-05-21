//
//  AccountTypeViewController.swift
//  MediDeals
//
//  Created by VLL on 2/18/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class AccountTypeViewController: UIViewController {
    
    @IBOutlet weak var proccedFutherBtn: DesignableButton!
    @IBOutlet weak var collectionView: UICollectionView!
    
    var AccType = [String]()
    var imgArr = [UIImage]()
    var cell = AccTypeViewCell()
    var selectedArry = NSMutableArray()
    var dummyArry = NSMutableArray()
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.isNavigationBarHidden = true
        AccType = ["WholeSeller","Retailer","PCD Company","Third Party Manufacturer","FMCG","Doctor"]
        self.imgArr = [UIImage(named: "wholesale"),UIImage(named: "retail"),UIImage(named: "enterprise"),UIImage(named: "merchant"),UIImage(named: "customer"),UIImage(named: "stethoscope")] as! [UIImage]
        
        self.proccedFutherBtn.isHidden = true
        self.dummyArry = NSMutableArray()
        self.selectedArry = NSMutableArray()
        for _ in 0..<self.AccType.count{
        self.dummyArry.add("0")
        }
        // Do any additional setup after loading the view.
    }
    
    @IBAction func backBtn(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
    @IBAction func proccedFurther(_ sender: DesignableButton) {
        if selectedArry.count > 2{
            Utilities.ShowAlertView2(title: "Alert", message: "Please choose one or maximum two account types to proceed further", viewController: self)
        }else{
            let vc = self.storyboard?.instantiateViewController(withIdentifier: "ChooseCategoryVC") as! ChooseCategoryVC
            SingletonVariables.sharedInstace.accountType = selectedArry[0] as! String
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }
    
}
@available(iOS 11.0, *)
extension AccountTypeViewController : UICollectionViewDelegate , UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return AccType.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! AccTypeViewCell
        cell.Namelbl.text = AccType[indexPath.row]
        cell.imgView.image = imgArr[indexPath.row]
        
        if dummyArry[indexPath.row] as! String == "0"{
            cell.imageCheck.isHidden = true
        }else{
            cell.imageCheck.isHidden = false
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if dummyArry[indexPath.row] as! String == "0"{
            self.dummyArry.replaceObject(at: indexPath.row, with: "1")
            selectedArry.add(AccType[indexPath.row])
        }else{
            self.dummyArry.replaceObject(at: indexPath.row, with: "0")
            selectedArry.remove(AccType[indexPath.row])
        }
        print(dummyArry)
        print(selectedArry)
        
        if selectedArry.count < 1{
            self.proccedFutherBtn.isHidden = true
        }else{
            self.proccedFutherBtn.isHidden = false
        }
        collectionView.reloadItems(at: [indexPath])
        
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
         return CGSize(width:(collectionView.frame.width)/3, height: 120)
    }
    
}
class AccTypeViewCell : UICollectionViewCell{
    @IBOutlet weak var imgView: UIImageView!
    @IBOutlet weak var Namelbl: UILabel!
    @IBOutlet weak var imageCheck: UIImageView!
}
