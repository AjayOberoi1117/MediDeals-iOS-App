//
//  Cart_ViewController.swift
//  MediDeals
//
//  Created by SIERRA on 1/2/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
@available(iOS 11.0, *)
class Cart_ViewController: UIViewController , UITextFieldDelegate{
    @IBOutlet weak var emptyCartImage: UIImageView!
    @IBOutlet weak var hiddenView: UIView!
    @IBOutlet var totalPrice: UILabel!
    @IBOutlet weak var popUpView: UIView!
    @IBOutlet var deleteBtn: UIButton!
    @IBOutlet weak var SubTotal: UILabel!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var cartTableView: UITableView!
      var tapGesture = UITapGestureRecognizer()
    var cell = Cart_TableViewCell()
    var getCartData = [getCartListing]()
    var quantityArray = [String]()
    var countValue = Int()
    var minQuantitiy = [String]()
    var newminQuantitiy = [String]()
    var productIdsArray = [String]()
    var grandToTal = Float()
    var playTime = Timer()
    var strLabel = UILabel()
    var checkAction = ""
    var login_status = ""
    //let id = self.getCartData[sender.tag].product_id
   let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    override func viewDidLoad() {
        super.viewDidLoad()
        self.hiddenView.isHidden = true
        self.popUpView.isHidden = true
        self.hiddenView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTappedOnCircularView1)))
        
        self.activityIndicator.isHidden =  true
        countValue = 1
        self.getCartApi()
        emptyCartImage.isHidden = true
        Utilities.HideRightSideMenu()
      //®  self.cartTableView.reloadData(effect: .LeftAndRight)
        // Do any additional setup after loading the view.
    }
    @objc func didTappedOnCircularView1(){
        print("someone tap me...")
        hiddenView.isHidden = true
        popUpView.isHidden = true
    }
    @IBAction func deleteCartBtn(_ sender: UIButton){
        let id = self.getCartData[sender.tag].product_id
        self.deletCartApi(prodID: id)
    }
    
    @IBAction func backBtn(_ sender: UIBarButtonItem){
//        if getCartData.count != 0{
//            //1771-12
////        let ids = self.productIdsArray.joined(separator: ",")
////        let finalQuantity = self.newminQuantitiy.joined(separator: ",")
//            var newArr = [String]()
//            for index in 0..<self.productIdsArray.count{
//                let a = self.productIdsArray[index]
//                let b = self.newminQuantitiy[index]
//                let c = a + "-" + b
//                print(c)
//                newArr.append(c)
//            }
//            print(newArr)
//            checkAction = "back"
//            let d = newArr.joined(separator: ",")
//            self.editCartApi(prodID: d)
//        }else{
            self.navigationController?.popViewController(animated: true)
//        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    @IBAction func checkoutBtn(_ sender: UIButton) {
//
//        var newArr = [String]()
//        for index in 0..<self.productIdsArray.count{
//            let a = self.productIdsArray[index]
//            let b = self.newminQuantitiy[index]
//            let c = a + "-" + b
//            print(c)
//            newArr.append(c)
//        }
//        print(newArr)
//        checkAction = "back"
//        let d = newArr.joined(separator: ",")
//        self.editCartApi(prodID: d)
        
        
        if self.login_status == "2"{
            UIView.animate(withDuration: 0.3, delay: 0, options: UIView.AnimationOptions.curveEaseOut, animations: {
                self.hiddenView.isHidden = false
                self.popUpView.isHidden = false
                self.view.layoutIfNeeded()
                
            }, completion: nil)
            
        }else{
            self.sague()
        }
        
    }
    @IBAction func regiserbtn(_ sender: UIButton) {
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "RegisterVC2") as! RegisterVC2
        self.navigationController?.pushViewController(vc, animated: true)
    }
    @IBAction func loginBtn(_ sender: UIButton) {
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "Login2ViewController") as! Login2ViewController
        self.navigationController?.pushViewController(vc, animated: true)
    }
    @IBAction func btnPlus(_ sender: UIButton){
        countValue = Int(self.newminQuantitiy[sender.tag])!
        countValue = (countValue + 1)
        print (countValue)
        self.newminQuantitiy[sender.tag] = "\(countValue)"
        let singlePrice:Float = Float(self.getCartData[sender.tag].price)!
        self.grandToTal = grandToTal + singlePrice
        print(self.grandToTal)
        self.totalPrice.text = "Total: Rs."
            +  "\(self.grandToTal)"
        self.SubTotal.text = "SubTotal: Rs."
            + "\(self.grandToTal)"
        cartTableView.reloadData()
     
               
    }
    @objc func runtiming(){
        playTime.invalidate()
    }
 
    @IBAction func btnMinus(_ sender: UIButton){
        countValue = Int(self.newminQuantitiy[sender.tag])!
        if countValue > Int(minQuantitiy[sender.tag]) ?? 0
        {
            countValue -= 1
            cell.lblValue.text = "\(countValue)"
            self.newminQuantitiy[sender.tag] = "\(countValue)"
            print(countValue)
            let singlePrice:Float = Float(self.getCartData[sender.tag].price)!
            self.grandToTal = grandToTal - singlePrice
            print(self.grandToTal)
            self.totalPrice.text = "Total: Rs."
                +  "\(self.grandToTal)"
            self.SubTotal.text = "SubTotal: Rs."
                + "\(self.grandToTal)"
        }

        cartTableView.reloadData()
        //let id = self.getCartData[sender.tag].product_id
        //self.editCartApi(prodID: id, quantity: "\(countValue)")
 }
    func textFieldDidBeginEditing(_ textField: UITextField) {
      print(textField.tag)
      
        
    }
    func textFieldDidEndEditing(_ textField: UITextField) {
        let productMinQ:Int = Int(self.newminQuantitiy[textField.tag])!
        if textField.text != ""  {
            if Int(textField.text!)! < productMinQ {
                Utilities.ShowAlertView2(title: "Alert", message: "Order quantity must me greater than minimum order quantity ", viewController: self)
            }else{
                print(textField.tag)
                let value = textField.text
                self.newminQuantitiy[textField.tag] = "\(value ?? "")"
                let singlePrice:Float = Float(self.getCartData[textField.tag].price)!
                let productQuantity:Float = Float(self.newminQuantitiy[textField.tag])!
                self.grandToTal = 0.0
                let newTotal:Float = singlePrice * productQuantity
                self.grandToTal = grandToTal + newTotal
                print(self.grandToTal)
                self.totalPrice.text = "Total: Rs."
                    +  "\(self.grandToTal)"
                self.SubTotal.text = "SubTotal: Rs."
                    + "\(self.grandToTal)"
            }
        }else if textField.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Please add some quantity", viewController: self)
        }
       
    }
    //MARK: GetProduct Cart API
    func getCartApi(){
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["device_id": UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String,
                      ]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.get_cart.caseValue,parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                self.getCartData = [getCartListing]()
                self.emptyCartImage.isHidden = false
                self.cartTableView.isHidden = true
                self.cartTableView.reloadData()
            } else {
                   self.stopAnim()
                self.login_status = "\(dic.value(forKeyPath: "record.login_status") as! NSNumber)"
                self.emptyCartImage.isHidden = true
                if let data = (dic.value(forKeyPath: "record.data") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    self.minQuantitiy = [String]()
                    self.newminQuantitiy = [String]()
                    self.productIdsArray = [String]()
                    self.getCartData = [getCartListing]()
                    
                    for index in 0..<data.count
                    {
                        self.getCartData.append(getCartListing(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title: "\((data[index] as AnyObject).value(forKey: "title") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", quantity: "\((data[index] as AnyObject).value(forKey: "min_quantity") ?? "")", total: "\((data[index] as AnyObject).value(forKey: "total") ?? "")"))
                        
                        self.minQuantitiy.append("\((data[index] as AnyObject).value(forKey: "min_quantity") ?? "")")
                        self.newminQuantitiy.append("\((data[index] as AnyObject).value(forKey: "quantity") ?? "")")
                        self.productIdsArray.append("\((data[index] as AnyObject).value(forKey: "product_id") ?? "")")
                    }
//                    for
                   
                    self.totalPrice.text = "Total: Rs."
                        + "\(dic.value(forKeyPath: "record.total") as! String)"
                    self.grandToTal = Float(dic.value(forKeyPath: "record.total") as! String)!
                    self.SubTotal.text = "SubTotal: Rs."
                        + "\(dic.value(forKeyPath: "record.subtotal") as! String)"
                    self.stopAnim()
                    
                   // UIView.transition(with: self.cartTableView,
//                                      duration: 0.35,
//                                      options: .transitionCrossDissolve,
//                                      animations: { self.cartTableView.reloadData() })
                    
                    self.cartTableView.reloadData()
                 }
            }
        }
    }
    func editCartApi(prodID:String){
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["device_id": UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String, "product_id": prodID]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.edit_cart.caseValue,parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            } else {
                self.stopAnim()
                if self.checkAction == "back"{
                    self.navigationController?.popViewController(animated: true)
                }else{
                    self.sague()
                    
                }
            }
        }
    }
    
    func sague(){
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "CheckOutViewController") as! CheckOutViewController
        self.navigationController?.pushViewController(vc, animated: true)
    }
    

    func deletCartApi(prodID:String){
        self.addLoadingIndicator()
        self.startAnim()
        let params = ["device_id": UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String, "product_id": prodID]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.delete_cart.caseValue,parameters: params) { (response) in
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
            }
        }
    }

 }
@available(iOS 11.0, *)
extension Cart_ViewController : UITableViewDelegate, UITableViewDataSource{
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        return self.getCartData.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        cell = cartTableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! Cart_TableViewCell
        cell.lblValue.tag = indexPath.row
//        cell.lblValue.delegate = self
        cell.btnPlus.tag = indexPath.row
        cell.minusBtn.tag = indexPath.row
        cell.deleteBtn.tag = indexPath.row
        cell.lblValue.text =  newminQuantitiy[indexPath.row]
        cell.productName.text =  self.getCartData[indexPath.row].title
        cell.price.text =  "Rs: " + self.getCartData[indexPath.row].price
        cell.quantity.text = "Minimum Order Quantity: " + self.getCartData[indexPath.row].quantity
        return cell
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
        //MARK:- Fade transition Animation
//        cell.alpha = 0
//        UIView.animate(withDuration: 0.33) {
//            cell.alpha = 1
//        }
        
        //MARK:- Curl transition Animation
//         cell.layer.transform = CATransform3DScale(CATransform3DIdentity, 1, -1, -1)
//
//         UIView.animate(withDuration: 1.0) {
//          cell.layer.transform = CATransform3DIdentity
//        }
        
        //MARK:- Frame Translation Animation
//        cell.layer.transform = CATransform3DTranslate(CATransform3DIdentity, -cell.frame.width, 1, 1)
//
//         UIView.animate(withDuration: 0.33) {
//          cell.layer.transform = CATransform3DIdentity
//         }
    }
    
    
//    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
//        return true
//    }
//    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
//        return UITableViewCellEditingStyle.delete
//    }
//    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
//        if editingStyle == .delete {
//            print("Deleted")
//            let id = self.getCartData[indexPath.row].product_id
//            self.deletCartApi(prodID: id)
//            //self.catNames.remove(at: indexPath.row)
//            //self.cartTableView.deleteRows(at: [indexPath], with: .automatic)
//            //            self.cartTableView.deleteRows(at: [indexPath], with: .automatic)
//        }
//    }
    
}
