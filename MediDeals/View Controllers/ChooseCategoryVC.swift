//  ChooseCategoryVC.swift
//  MediDeals
//
//  Created by SIERRA on 2/21/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class ChooseCategoryVC: UIViewController {
    @IBOutlet weak var proccedFutherBtn: DesignableButton!
    @IBOutlet weak var collectionView: UICollectionView!
    
    var titleName = [String]()
    var titleIDs = [String]()
    var imagesArry = [UIImage]()
    var selectedArry = NSMutableArray()
    var selectedIDArry = NSMutableArray()

    var dummyArry = NSMutableArray()
    override func viewDidLoad() {
        super.viewDidLoad()
        titleName = ["Allopathic", "Ayurvedic", "FMCG","PCD/3rd Party","Surgical Goods","Generics"]
        titleIDs = ["1","2","3","4","5","6"]
        self.imagesArry = [UIImage(named: "Allopathi"),UIImage(named: "ayurvedi"),UIImage(named: "customer"),UIImage(named: "pharmac"),UIImage(named: "Surgica"),UIImage(named: "generi")] as! [UIImage]
        // Do any additional setup after loading the view.
        self.proccedFutherBtn.isHidden = true
        self.dummyArry = NSMutableArray()
        self.selectedArry = NSMutableArray()
        self.selectedIDArry = NSMutableArray()
        for _ in 0..<self.titleName.count{
            self.dummyArry.add("0")
        }
    }
    @IBAction func proccedFurther(_ sender: DesignableButton) {
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "Register_ViewController") as! Register_ViewController
        print(selectedIDArry)
        let a = selectedIDArry.componentsJoined(by: ",")
        SingletonVariables.sharedInstace.AccountCategory = a
        self.navigationController?.pushViewController(vc, animated: true)
     
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func backBtn(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
   
}

@available(iOS 11.0, *)
extension ChooseCategoryVC : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return titleName.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath as IndexPath) as? categoryCollectionView
        {
            //cell.menuView.backgroundColor = colorArray[indexPath.row]
            cell.lblCategory.text = titleName[indexPath.row]
            cell.imgView.image = imagesArry[indexPath.row]
            if dummyArry[indexPath.row] as! String == "0"{
                cell.imageCheck.isHidden = true
            }else{
                cell.imageCheck.isHidden = false
            }
            return cell
        }
        return UICollectionViewCell()
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if dummyArry[indexPath.row] as! String == "0"{
            self.dummyArry.replaceObject(at: indexPath.row, with: "1")
            selectedArry.add(titleName[indexPath.row])
            selectedIDArry.add(titleIDs[indexPath.row])
        }else{
            self.dummyArry.replaceObject(at: indexPath.row, with: "0")
            selectedArry.remove(titleName[indexPath.row])
            selectedIDArry.add(titleIDs[indexPath.row])
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
        return CGSize(width:(collectionView.frame.width)/3-10, height: 120)
    }
    
    
}

class categoryCollectionView : UICollectionViewCell{
    @IBOutlet var lblCategory: UILabel!
    @IBOutlet var imgView: UIImageView!
    @IBOutlet weak var imageCheck: UIImageView!
}
