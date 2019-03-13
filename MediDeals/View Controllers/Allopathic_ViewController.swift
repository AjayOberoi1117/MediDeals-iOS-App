//
//  Allopathic_ViewController.swift
//  MediDeals
//
//  Created by Pankaj Rana on 30/12/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit
import CRRefresh
@available(iOS 11.0, *)
class Allopathic_ViewController: UIViewController{
    @IBOutlet var lblTitleName: UILabel!
    @IBOutlet weak var collectionView: UICollectionView!
    var titleName: String?
    var getAllpothicData = [getAllopathicProducts]()
    var BlackView = UIView()
    var fliterMenuViewController = FilterViewController()
    var isMenuOpened:Bool = false
    var transition = CATransition()
    var withDuration = 0.5
    override func viewDidLoad() {
        super.viewDidLoad()
        //Utilities.AttachSideMenuController()
        if titleName == "Ayurvedic"{
            self.title = "AYURVEDIC"
            self.lblTitleName.text = "Ayurvedic"
        }else{
            self.title = "ALLOPATHIC"
            self.lblTitleName.text = "Allopathic"
            self.AllopathicPrductApi()
        }
        
        fliterMenuViewController = storyboard!.instantiateViewController(withIdentifier: "FilterViewController") as! FilterViewController
        
        let topBarHeight = UIApplication.shared.statusBarFrame.size.height +
            (self.navigationController?.navigationBar.frame.height ?? 0.0)
        
        fliterMenuViewController.view.frame = CGRect(x: 100, y: topBarHeight, width:UIScreen.main.bounds.size.width-100, height: UIScreen.main.bounds.size.height-topBarHeight)
        
        BlackView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height))
        BlackView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        self.view.addSubview(BlackView)
        BlackView.isHidden = true
        
        collectionView.cr.addHeadRefresh(animator: SlackLoadingAnimator()) { [weak self] in
            /// start refresh
            /// Do anything you want...
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                /// Stop refresh when your job finished, it will reset refresh footer if completion is true
                self?.collectionView.cr.endHeaderRefresh()
            })
        }
        collectionView.cr.beginHeaderRefresh()
        
    }
    
    func openAndCloseMenu(){
        if(isMenuOpened){
            isMenuOpened = false
            let button1 = UIBarButtonItem(image: UIImage(named: "menu"), style: .plain, target: self, action: #selector(MenuClick))
            self.navigationItem.leftBarButtonItem  = button1
            
            //            transition.duration = withDuration
            //            transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            //            transition.type = kCATransitionFade
            //            transition.subtype = kCATransitionFromLeft
            //            fliterMenuViewController.view.layer.add(transition, forKey: kCATransition)
            BlackView.isHidden = true
            fliterMenuViewController.willMove(toParentViewController: nil)
            fliterMenuViewController.view.removeFromSuperview()
            fliterMenuViewController.removeFromParentViewController()
        }
        else{
            isMenuOpened = true
             Utilities.HideLeftSideMenu()
            self.navigationItem.leftBarButtonItem = nil
            //            transition.duration = withDuration
            //            transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            //            transition.type = kCATransitionPush
            //            transition.subtype = kCATransitionFromRight
            //            fliterMenuViewController.view.layer.add(transition, forKey: kCATransition)
            BlackView.isHidden = false
            self.addChildViewController(fliterMenuViewController)
            self.view.addSubview(fliterMenuViewController.view)
            
            fliterMenuViewController.didMove(toParentViewController: self)
        }
        
    }
        
  
    @objc func MenuClick(){
        print("clicked")
        Utilities.AttachSideMenuController()
        Utilities.LeftSideMenu()
    }
    
    @IBAction func filterBtnAct(_ sender: UIBarButtonItem) {
        //Utilities.RightSideMenu()
        openAndCloseMenu()
    }
    @IBAction func menuAct(_ sender: UIBarButtonItem) {
        Utilities.LeftSideMenu()
    }
  //MARK: AllopathicProduct_API
    func AllopathicPrductApi(){
        let params = ["vendor_id": UserDefaults.standard.value(forKey: "USER_ID") as! String]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.get_products.caseValue,parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.hideProgress()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            } else {
                if let data = (dic.value(forKey: "record") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    for index in 0..<data.count
                    {
                        self.getAllpothicData.append(getAllopathicProducts(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((data[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((data[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((data[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", min_quantity: "", product_status: "\((data[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                    }
                   self.collectionView.reloadData()
                    
        }
    }
}
}
}
@available(iOS 11.0, *)
extension Allopathic_ViewController : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if self.getAllpothicData.count != 0{ return self.getAllpothicData.count }
        else{ return 0 }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell{
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath as IndexPath) as? MenuCollectionViewCell
        {
            
            cell.titleName.text = self.getAllpothicData[indexPath.row].title
            cell.disPriceLbl.text = "Rs " + self.getAllpothicData[indexPath.row].price
            let newStringStrike = "Rs " + self.getAllpothicData[indexPath.row].old_price
            let attributeString = NSMutableAttributedString(string: newStringStrike)
            attributeString.addAttribute(NSAttributedStringKey.strikethroughStyle, value: 1, range: NSMakeRange(0, attributeString.length))
            cell.originalPrice.attributedText = attributeString
             cell.codelbl.text = self.getAllpothicData[indexPath.row].code
            let d = Float(self.getAllpothicData[indexPath.row].discount)!.rounded(.towardZero)
            print("discount value is" , d)
            cell.discountPercent.text = String(format: "%.0f" , d) + "%"
            return cell
        }
        return UICollectionViewCell()
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
        vc.selectedProductID = self.getAllpothicData[indexPath.row].product_id
        self.navigationController?.pushViewController(vc, animated: true)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width:(collectionView.frame.width)/2-5, height: 160)
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let a = cell as? MenuCollectionViewCell{
            a.discountPercent.startAnimation()
        }
      }
    
}
