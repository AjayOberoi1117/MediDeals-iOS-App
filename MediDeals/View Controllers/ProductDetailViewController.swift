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
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideRightSideMenu()
        
        // Do any additional setup after loading the view.
    }
    override func viewWillAppear(_ animated: Bool) {
        if selectedProductID != ""{
            getProductdetailApi()
        }else{
            
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
    

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
   //MARK: GetProduct Cart API
    func getProductdetailApi(){
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["vendor_id": UserDefaults.standard.value(forKey: "USER_ID") as! String,
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
                    if self.product_status == "already_added"{
                        self.addtoCart.backgroundColor = BUTTONSELECTION_COLOR
                        self.addtoCart.setTitle("Go to Cart", for: .normal)
                    }else{
                        self.addtoCart.backgroundColor = BUTTON_COLOR
                        self.addtoCart.setTitle("Add to Cart", for: .normal)
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
                let alert = UIAlertController(title: "Message", message: (dic.value(forKey: "message") as! String), preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: "Continue", style: UIAlertActionStyle.default, handler: { action in
                    self.dismiss(animated: true, completion: nil)
                let vc = self.storyboard?.instantiateViewController(withIdentifier: "Cart_ViewController") as! Cart_ViewController
                    vc.minQuantitiy =  [self.min_quantity]
                    self.navigationController?.pushViewController(vc, animated: true)
                }))
                self.present(alert, animated: true, completion: nil)
                
            }
        }
    }
   
}
