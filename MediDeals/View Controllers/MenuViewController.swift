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
class MenuViewController: UIViewController,UISearchBarDelegate,UIScrollViewDelegate{
    @IBOutlet weak var searchView: UIView!
    @IBOutlet weak var TableViewTopConstraints: NSLayoutConstraint!
    @IBOutlet weak var searchProductTxt: UISearchBar!
    @IBOutlet var noDataImage: UIImageView!
    @IBOutlet var tableViewData: UITableView!
    @IBOutlet weak var searchBtn: UIButton!
    @IBOutlet weak var filterBtn: UIButton!
    var params = [String:String]()
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
    var index = 0
    var getAllDataArr = NSArray()
    var filteredArr = NSMutableArray()
    var search_text:String!
    var isSearchActive: Bool = false
    var isSearch = "no"
    var pageno = Int()
    var totalPage = Int()
    var checkClick = ""
    override func viewDidLoad() {
        super.viewDidLoad()
        //Utilities.AttachSideMenuController()
        searchProductTxt.delegate = self
        searchView.isHidden = true
        TableViewTopConstraints.constant = 0
        pageno = 1
        fliterMenuViewController = storyboard!.instantiateViewController(withIdentifier: "FilterViewController") as! FilterViewController
        let topBarHeight = UIApplication.shared.statusBarFrame.size.height +
            (self.navigationController?.navigationBar.frame.height ?? 0.0)
        fliterMenuViewController.view.frame = CGRect(x: 100, y: topBarHeight, width:UIScreen.main.bounds.size.width-100, height: UIScreen.main.bounds.size.height-topBarHeight)
        BlackView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height))
        BlackView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        self.view.addSubview(BlackView)
        BlackView.isHidden = true
        
        // Do any additional setup after loading the view.
        
        tableViewData.cr.addHeadRefresh(animator: SlackLoadingAnimator()) { [weak self] in
            /// start refresh
            /// Do anything you want...
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                /// Stop refresh when your job finished, it will reset refresh footer if completion is true
                self?.tableViewData.cr.endHeaderRefresh()
            })
        }
         tableViewData.cr.beginHeaderRefresh()
        
        self.CallFn()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
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
            self.noDataImage.isHidden = true
        }
        else if titleName == "PCD/3rd Party"{
            self.title = "PCD/3rd Party"
            self.noDataImage.isHidden = true
            self.AllopathicPrductApi(cat_id: catID)
            
        }else if titleName == "Surgical Goods"{
            self.title = "Surgical Goods"
            self.noDataImage.isHidden = true
            self.AllopathicPrductApi(cat_id: catID)
        }else if titleName == "Generics"{
            self.title = "Generics"
            self.noDataImage.isHidden = true
            self.AllopathicPrductApi(cat_id: catID)
        }
        
        SingletonVariables.sharedInstace.cat_id = catID

    }
    override func didReceiveMemoryWarning(){
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    override func viewWillAppear(_ animated: Bool){
       
    }
    func openAndCloseMenu(){
        if(isMenuOpened){
            isMenuOpened = false
            let button1 = UIBarButtonItem(image: UIImage(named: "menu"), style: .plain, target: self, action: #selector(MenuClick))
            self.navigationItem.leftBarButtonItem  = button1
            let button2 = UIBarButtonItem(image: UIImage(named: "filter"), style: .plain, target: self, action: #selector(MenuClick2))
            
            self.navigationItem.rightBarButtonItem  = button2
            //            transition.duration = withDuration
            //            transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            //            transition.type = kCATransitionFade
            //            transition.subtype = kCATransitionFromLeft
            //            fliterMenuViewController.view.layer.add(transition, forKey: kCATransition)
            BlackView.isHidden = true
            fliterMenuViewController.willMove(toParent: nil)
            fliterMenuViewController.view.removeFromSuperview()
            fliterMenuViewController.removeFromParent()
        }
        else{
            isMenuOpened = true
            Utilities.HideLeftSideMenu()
            self.searchBtn.isHidden = true
            let button1 = UIBarButtonItem(image: UIImage(named: "tick"), style: .plain, target: self, action: #selector(MenuClick1))
            let button2 = UIBarButtonItem(image: UIImage(named: "close"), style: .plain, target: self, action: #selector(MenuClick2))
            
            self.navigationItem.leftBarButtonItem  = button2
            
            
            self.navigationItem.rightBarButtonItem = button1
            //            transition.duration = withDuration
            //            transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            //            transition.type = kCATransitionPush
            //            transition.subtype = kCATransitionFromRight
            //            fliterMenuViewController.view.layer.add(transition, forKey: kCATransition)
            BlackView.isHidden = false
            self.addChild(fliterMenuViewController)
            self.view.addSubview(fliterMenuViewController.view)
            fliterMenuViewController.didMove(toParent: self)
        }
}
 
    @objc func MenuClick(){
        print("clicked")
        Utilities.AttachSideMenuController()
        Utilities.LeftSideMenu()
    }
     @objc func MenuClick1(){
        checkClick = "yes"
        print(SingletonVariables.sharedInstace.FilterDic)
        openAndCloseMenu()
         CallFn()
    }
    @objc func MenuClick2(){
        
        openAndCloseMenu()
    }
    
    @IBAction func filterBtnAct(_ sender: UIButton) {
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
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if ((tableViewData.contentOffset.y + tableViewData.frame.size.height) >= tableViewData.contentSize.height)
        {
            pageno = pageno+1
            if totalPage >= pageno{
                self.CallFn()
            }
            
            tableViewData.cr.addFootRefresh(animator: NormalFooterAnimator()) { [weak self] in
                /// start refresh
                /// Do anything you want...
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                    /// Stop refresh when your job finished, it will reset refresh footer if completion is true
                    
                })
            }
            
//            UIView.transition(with: self.tableViewData,
//                              duration: 0.35,
//                              options: .transitionFlipFromLeft,
//                              animations: { self.tableViewData.reloadData() })
        }
    }
    
    //MARK: AllopathicProduct_API
    func AllopathicPrductApi(cat_id:String){
        tableViewData.cr.beginHeaderRefresh()
        
        if checkClick == "yes"{
           params = SingletonVariables.sharedInstace.FilterDic
        }else{
         params = ["device_id": UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String,
                      "cat_id": cat_id,
                      "minPrice": "1",
                      "maxPrice": "5000",
                      "search": "",
                      "discount": "",
                      "brand": "",
                      "state":"",
                      "city": "",
                      "page_no": "\(pageno)"]
        }
        
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.search.caseValue,parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
           
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                //Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
                self.noDataImage.isHidden = false
                self.tableViewData.cr.endHeaderRefresh()
                self.tableViewData.cr.removeFooter()
            }else{
                 self.totalPage = (dic.value(forKey: "totalpage") as! NSString).integerValue
                self.tableViewData.cr.endHeaderRefresh()
                self.tableViewData.cr.removeFooter()
                if let data = (dic.value(forKey: "result") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    if data.count == 0{
                        self.stopAnim()
                        self.noDataImage.isHidden = false
                        Utilities.ShowAlertView2(title: "Alert", message: "No Records Found!", viewController: self)
                    }else{
                        self.noDataImage.isHidden = true
                        self.getAllDataArr = NSArray()
                        self.getAllDataArr = data
                        self.productStatusArr = [String]()
                        self.getAllpothicData = [getAllopathicProducts]()
                        for index in 0..<data.count
                        {
                            self.getAllpothicData.append(getAllopathicProducts(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((data[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((data[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((data[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((data[index] as AnyObject).value(forKey: "barnd_name") ?? "")", min_quantity: "\((data[index] as AnyObject).value(forKey: "minquantity") ?? "")", product_status: "\((data[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                            
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
//                        UIView.transition(with: self.tableViewData,
//                                          duration: 0.35,
//                                          options: .transitionFlipFromLeft,
//                                          animations: { self.tableViewData.reloadData() })
                        
                        self.tableViewData.reloadData()
                        
                    }
                }
            }
        }
    }
    func addtoCartApi(productid:String,quantity:String){
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["device_id": UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String,
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
    
   
    
    //MARK: ...FOR SEARCH BAR DELEGATE...
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchProductTxt.endEditing(true)
        
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.count == 0 {
            isSearchActive = false
            searchProductTxt.resignFirstResponder()
            filteredArr = NSMutableArray()
            self.CallFn()
        }else{
            self.textMatch(textTyped: searchText)
        }
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        //        searchBar_out.tintColor = UIColor.white
        searchProductTxt.showsCancelButton = true
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchProductTxt.showsCancelButton = false
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
         searchProductTxt.endEditing(true)
        if searchProductTxt.text!.count != 0 {
            isSearchActive = false
            filteredArr = NSMutableArray()
            self.CallFn()
            
        }
    }
    func textMatch(textTyped: String) {
        if textTyped != "" {
            isSearchActive = true
            filteredArr.removeAllObjects()
            let predicate2 = NSPredicate(format: "title BEGINSWITH[c] %@", textTyped)
            filteredArr = NSMutableArray(array: self.getAllDataArr.filtered(using: predicate2))
            
            print("new array is ++++++\(filteredArr)")
            
            self.getAllpothicData = [getAllopathicProducts]()
            for index in 0..<filteredArr.count
            {
                self.getAllpothicData.append(getAllopathicProducts(product_id: "\((filteredArr[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((filteredArr[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((filteredArr[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((filteredArr[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((filteredArr[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((filteredArr[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((filteredArr[index] as AnyObject).value(forKey: "brand_name") ?? "")", min_quantity: "\((filteredArr[index] as AnyObject).value(forKey: "minquantity") ?? "")", product_status: "\((filteredArr[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                
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
        else {
            isSearchActive = false
            searchProductTxt.endEditing(true)
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
        vc.isComeFrom = "menu"
        vc.selectedProductID = self.getAllpothicData[indexPath.row].product_id
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        cell1 = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MenuTableViewCell
            cell1.addtoCart.tag = indexPath.row
            if dummyArry[indexPath.row] == "1"{
                cell1.addtoCart.backgroundColor = BUTTONSELECTION_COLOR
                 cell1.addtoCart.setTitle("GO TO CART", for: .normal)
            }else{
                cell1.addtoCart.backgroundColor = BUTTON_COLOR
                cell1.addtoCart.setTitle("ADD TO CART", for: .normal)
            }
            
            cell1.titleName.text = self.getAllpothicData[indexPath.row].title
            cell1.disPriceLbl.text = "Rs " + self.getAllpothicData[indexPath.row].price
            let newStringStrike = "Rs " + self.getAllpothicData[indexPath.row].old_price
            let attributeString = NSMutableAttributedString(string: newStringStrike)
        attributeString.addAttribute(NSAttributedString.Key.strikethroughStyle, value: 1, range: NSMakeRange(0, attributeString.length))
            cell1.originalPrice.attributedText = attributeString
            //cell1.codelbl.text = self.getAllpothicData[indexPath.row].code
            cell1.brandName.text = self.getAllpothicData[indexPath.row].brandName
            let d = Float(self.getAllpothicData[indexPath.row].discount)!.rounded(.towardZero)
            print("discount value is" , d)
           // cell1.discountPercent.startAnimation()
            cell1.discountPercent.text = String(format: "%.0f" , d) + "%"
            cell1.quantity.text = "Minimum Order Quantity: " + self.getAllpothicData[indexPath.row].min_quantity
        
        
            return cell1
        
    }
    
//    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath){
//        //let cell1 = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MenuTableViewCell
//        cell1.discountPercent.startAnimation()
//
//        //MARK:- Curl transition Animation
//        cell.layer.transform = CATransform3DScale(CATransform3DIdentity, 1, -1, -1)
//
//        UIView.animate(withDuration: 1.0) {
//            cell.layer.transform = CATransform3DIdentity
//        }
//    }
//
    
   
    
    
    //    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    //        let vc = self.storyboard?.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
    //        self.navigationController?.pushViewController(vc, animated: true)
    //    }
    
}
