//
//  MenuViewController.swift
//  MediDeals
//
//  Created by SIERRA on 1/31/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
import CRRefresh
@available(iOS 11.0, *)
class MenuViewController: UIViewController {
    
    @IBOutlet var noDataImage: UIImageView!
    @IBOutlet var tableViewData: UITableView!
    var cell1 = MenuTableViewCell()
    var dummyArry = [String]()
    var productStatusArr = [String]()
    var titleName = ""
    var catID = ""
    var getAllpothicData = [getAllopathicProducts]()
    var BlackView = UIView()
    var fliterMenuViewController = FilterViewController()
    var isMenuOpened:Bool = false
    var transition = CATransition()
    var withDuration = 0.5
    override func viewDidLoad() {
        super.viewDidLoad()
        //Utilities.AttachSideMenuController()
        fliterMenuViewController = storyboard!.instantiateViewController(withIdentifier: "FilterViewController") as! FilterViewController
        let topBarHeight = UIApplication.shared.statusBarFrame.size.height +
            (self.navigationController?.navigationBar.frame.height ?? 0.0)
        fliterMenuViewController.view.frame = CGRect(x: 100, y: topBarHeight, width:UIScreen.main.bounds.size.width-100, height: UIScreen.main.bounds.size.height-topBarHeight)
        BlackView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height))
        BlackView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        self.view.addSubview(BlackView)
        BlackView.isHidden = true
        
        // Do any additional setup after loading the view.
        
       
    }
    
    override func viewDidAppear(_ animated: Bool) {
        tableViewData.cr.addHeadRefresh(animator: SlackLoadingAnimator()) { [weak self] in
            /// start refresh
            /// Do anything you want...
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                /// Stop refresh when your job finished, it will reset refresh footer if completion is true
                self?.tableViewData.cr.endHeaderRefresh()
            })
        }
       // tableViewData.cr.beginHeaderRefresh()
    }
    func CallFn(){
        if titleName == "Ayurvedic"{
            self.title = "AYURVEDIC"
            self.noDataImage.isHidden = true
            self.AllopathicPrductApi(cat_id: catID)
        }else if titleName == "Allopathic"{
            self.title = "ALLOPATHIC"
            self.AllopathicPrductApi(cat_id: self.catID)
            self.noDataImage.isHidden = true
        }
        else if titleName == "FMCG"{
            self.title = "FMCG"
            self.AllopathicPrductApi(cat_id: self.catID)
            self.noDataImage.isHidden = false
        }
        else if titleName == "PCD/3rd Party"{
            self.title = "PCD/3rd Party"
            self.noDataImage.isHidden = false
            
        }else if titleName == "Surgical Goods"{
            self.title = "Surgical Goods"
            self.noDataImage.isHidden = false
        }else if titleName == "Generics"{
            self.title = "Generics"
            self.noDataImage.isHidden = false
        }

    }
    override func didReceiveMemoryWarning(){
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    override func viewWillAppear(_ animated: Bool){
        self.CallFn()
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
    @IBAction func AddCartBTn(_ sender: UIButton) {
        print(sender.tag)
        if  self.dummyArry[sender.tag] == "0" {
            self.dummyArry.insert("1", at: sender.tag)
            self.addtoCartApi(productid: self.getAllpothicData[sender.tag].product_id, quantity: self.getAllpothicData[sender.tag].min_quantity)
            let indexPath = IndexPath(item: sender.tag, section: 0)
            tableViewData.reloadRows(at: [indexPath], with: .automatic)
        }else{
            let vc = self.storyboard?.instantiateViewController(withIdentifier: "Cart_ViewController") as! Cart_ViewController
            self.navigationController?.pushViewController(vc, animated: true)
            
        }
    }
    @IBAction func menuAct(_ sender: UIBarButtonItem){
        Utilities.LeftSideMenu()
    }
    //MARK: AllopathicProduct_API
    func AllopathicPrductApi(cat_id:String){
         self.addLoadingIndicator()
        self.startAnim()
        let params = ["vendor_id": UserDefaults.standard.value(forKey: "USER_ID") as! String, "cat_id": cat_id]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.get_cat_products.caseValue,parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            }else{
                if let data = (dic.value(forKey: "record") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    self.productStatusArr = [String]()
                    self.getAllpothicData = [getAllopathicProducts]()
                    for index in 0..<data.count
                    {
                        self.getAllpothicData.append(getAllopathicProducts(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((data[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((data[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((data[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((data[index] as AnyObject).value(forKey: "brand_name") ?? "")", min_quantity: "\((data[index] as AnyObject).value(forKey: "min_quantity") ?? "")", product_status: "\((data[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                        
                    }
                    self.dummyArry = [String]()
                    for index1 in 0..<self.getAllpothicData.count{
                        let a = self.getAllpothicData[index1].product_status
                        if a == "already_added"{
                            self.dummyArry.append("1")
                        }else{
                            self.dummyArry.append("0")
                        }
                    }
                    self.stopAnim()
                    self.tableViewData.reloadData()
                }
            }
        }
    }
    func addtoCartApi(productid:String,quantity:String){
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["user_id": UserDefaults.standard.value(forKey: "USER_ID") as! String,
                      "product_id" : productid ,
                      "quantity": quantity]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.add_Cart.caseValue,parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
                
            } else {
                self.stopAnim()
                //Utilities.ShowAlertView2(title: "Message", message: dic.value(forKey: "message") as! String, viewController: self)
                  //self.CallFn()
            }
        }
    }
}
@available(iOS 11.0, *)
extension MenuViewController : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        if self.getAllpothicData.count != 0{ return self.getAllpothicData.count }
        else{ return 0 }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
        vc.selectedProductID = self.getAllpothicData[indexPath.row].product_id
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        cell1 = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MenuTableViewCell
            cell1.addtoCart.tag = indexPath.row
            if dummyArry[indexPath.row] == "1"{
                cell1.addtoCart.backgroundColor = BUTTONSELECTION_COLOR
                 cell1.addtoCart.setTitle("Go to Cart", for: .normal)
            }else{
                cell1.addtoCart.backgroundColor = BUTTON_COLOR
                cell1.addtoCart.setTitle("Add to Cart", for: .normal)
            }
            
            cell1.titleName.text = self.getAllpothicData[indexPath.row].title
            cell1.disPriceLbl.text = "Rs " + self.getAllpothicData[indexPath.row].price
            let newStringStrike = "Rs. " + self.getAllpothicData[indexPath.row].old_price
            let attributeString = NSMutableAttributedString(string: newStringStrike)
            attributeString.addAttribute(NSAttributedStringKey.strikethroughStyle, value: 1, range: NSMakeRange(0, attributeString.length))
            cell1.originalPrice.attributedText = attributeString
            cell1.codelbl.text = self.getAllpothicData[indexPath.row].code
            cell1.brandName.text = self.getAllpothicData[indexPath.row].brandName
            let d = Float(self.getAllpothicData[indexPath.row].discount)!.rounded(.towardZero)
            print("discount value is" , d)
            cell1.discountPercent.startAnimation()
            cell1.discountPercent.text = String(format: "%.0f" , d) + "%"
            cell1.quantity.text = "Minimum Order Quantity: " + self.getAllpothicData[indexPath.row].min_quantity
            return cell1
        
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath){
        let cell1 = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MenuTableViewCell
        cell1.discountPercent.startAnimation()
    }
    
    //    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    //        let vc = self.storyboard?.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
    //        self.navigationController?.pushViewController(vc, animated: true)
    //    }
    
}
