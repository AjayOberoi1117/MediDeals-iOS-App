//
//  ProductDetailViewController.swift
//  MediDeals
//
//  Created by SIERRA on 12/31/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class ProductDetailViewController: UIViewController {

    @IBOutlet weak var continueShoppingBtn: DesignableButton!
    @IBOutlet weak var addtoCart: DesignableButton!
    @IBOutlet weak var proImage: UIImageView!
    @IBOutlet weak var lblTitleName: UILabel!
    @IBOutlet weak var disPrice: UILabel!
    @IBOutlet weak var quantity: UILabel!
    @IBOutlet weak var disPercentage: UILabel!
    @IBOutlet weak var category: UILabel!
    @IBOutlet weak var locations: UILabel!
    
    var selectedProductID = ""
    var min_quantity = ""
    var productId = ""
    var product_status = ""
    var isComeFrom = ""
    var btnBarBadge : MJBadgeBarButton!
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideRightSideMenu()
        self.addtoCart.isHidden = true
        self.continueShoppingBtn.isHidden = true
        // Do any additional setup after loading the view.
    }
    override func viewWillAppear(_ animated: Bool) {
        if selectedProductID != ""{
            cartbtn()
            self.getCartApi()
            getProductdetailApi()
        }else{
            
        }
    }
    func cartbtn(){
        let customButton = UIButton(type: UIButton.ButtonType.custom)
        customButton.frame = CGRect(x: 0, y: 0, width: 35.0, height: 35.0)
        customButton.addTarget(self, action: #selector(self.onBagdeButtonClick), for: .touchUpInside)
        customButton.setImage(UIImage(named: "shopping-cart"), for: .normal)
        
        self.btnBarBadge = MJBadgeBarButton()
        self.btnBarBadge.setup(customButton: customButton)
        self.btnBarBadge.badgeValue = "0"
        self.btnBarBadge.badgeOriginX = 20.0
        self.btnBarBadge.badgeOriginY = -4
        
        self.navigationItem.rightBarButtonItem = self.btnBarBadge
        
    }
    
    @objc func onBagdeButtonClick() {
        print("button Clicked \(self.btnBarBadge.badgeValue)")
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "Cart_ViewController") as! Cart_ViewController
        self.navigationController?.pushViewController(vc, animated: true)
    }
    @IBAction func contiShoppingAct(_ sender: DesignableButton) {
        if isComeFrom == "home"{
            self.navigationController?.popViewController(animated: true)
        }else{
            performPushSeguefromController(identifier: "Home_ViewController")
        }
    }
    @IBAction func addToCart(_ sender: DesignableButton) {
       
        if self.product_status == "already_added"{
            let vc = self.storyboard?.instantiateViewController(withIdentifier: "Cart_ViewController") as! Cart_ViewController
            vc.minQuantitiy =  [self.min_quantity]
            self.navigationController?.pushViewController(vc, animated: true)
        }else{
            self.addtoCartApi()
        }
    }
    
    func getCartApi(){
        let params = ["device_id": UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String,
        ]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.get_cart.caseValue,parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                
            } else {
                self.stopAnim()
                let a = dic.value(forKey: "total_items") as! NSNumber
                self.btnBarBadge.badgeValue = "\(Int(truncating: a))"
            }
        }
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
   //MARK: GetProduct Cart API
    func getProductdetailApi(){
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["device_id": UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String,
                      "product_id" : self.selectedProductID ]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.get_product_detail.caseValue,parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            } else {
                self.stopAnim()
                if let data = dic.value(forKey: "record") as? NSDictionary
                {
                    self.title = (data.value(forKey: "title") as! String)
                    self.lblTitleName.text = "Max Retail Price: Rs " + "\(data.value(forKey: "old_price") as! String)"
                    self.disPrice.text = "Discounted Price:  Rs " + "\(data.value(forKey: "price") as! String)"
                    self.quantity.text = "Minimum Order Quantity: " + "\(data.value(forKey: "min_quantity") as! String)"
                    self.disPercentage.text = "Discount: " + "\(data.value(forKey: "discount") as! String)" + "%"
                    self.category.text = "Categories: " + "\(String(describing: data.value(forKey: "cat_name") as! String))"
                    self.locations.text = "Delivery Locations: " + "\(data.value(forKey: "location") as! String)"
                    self.min_quantity = data.value(forKey: "min_quantity") as! String
                    self.productId = data.value(forKey: "product_id") as! String
                    
                    self.product_status = data.value(forKey: "product_status") as! String
                    self.addtoCart.isHidden = false
                    self.continueShoppingBtn.isHidden = false
                    if self.product_status == "already_added"{
                        self.addtoCart.backgroundColor = BUTTONSELECTION_COLOR
                        self.addtoCart.setTitle("GO TO CART", for: .normal)
                    }else{
                        self.addtoCart.backgroundColor = BUTTON_COLOR
                        self.addtoCart.setTitle("ADD TO CART", for: .normal)
                    }
                }
            }
        }
    }
    //MARK: Add To cart API
    
    @IBAction func cartBtn(_ sender: UIBarButtonItem){
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "Cart_ViewController") as! Cart_ViewController
        self.navigationController?.pushViewController(vc, animated: true)
    }
    func addtoCartApi(){
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["device_id": UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String,
                      "product_id" : self.productId ,
                      "quantity": self.min_quantity]
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
                self.getCartApi()
                self.getProductdetailApi()
            }
        }
    }
   
}
