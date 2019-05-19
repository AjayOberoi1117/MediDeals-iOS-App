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
    let model = generateRandomData()
    var storedOffsets = [Int: CGFloat]()
    var colorArray = [UIColor]()
    var titleName = [String]()
    var imagesArry = [UIImage]()
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideRightSideMenu()
        // Do any additional setup after loading the view.
        colorArray = [FIRST_COLOR,SECOND_COLOR,THIRD_COLOR,FOURTH_COLOR,FIRST_COLOR,SECOND_COLOR,THIRD_COLOR]
        titleName = ["Wholeseller Zone","Add Product","Show all Products","Subscription","Order Received","Bank Details","Uplaod Data"]
     self.imagesArry = [UIImage(named: "seller")!,UIImage(named: "add")!,UIImage(named: "list")!,UIImage(named: "package")!,UIImage(named: "shopping-bag")!,UIImage(named: "bank-building")!,UIImage(named: "file")!]
//        self.addLoadingIndicator()
//         self.startAnim()
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
extension MyAccountViewController : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
         return 7
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath as IndexPath) as? AccountCollectionViewCell
        {
            cell.menuView.backgroundColor = colorArray[indexPath.row]
            cell.titleName.text = titleName[indexPath.row]
            cell.MenuImage.image = imagesArry[indexPath.row]
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
