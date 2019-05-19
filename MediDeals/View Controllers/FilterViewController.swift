//
//  FilterViewController.swift
//  MediDeals
//
//  Created by Pankaj Rana on 06/01/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class FilterViewController: UIViewController,LBZSpinnerDelegate {
    func spinnerChoose(_ spinner: LBZSpinner, index: Int, value: String) {
        var spinnerName = ""
        if spinner == brandSpinner { spinnerName = "brandSpinner"
            selectedBrand = value
        }
        if spinner == stateSpinner {
            print("Spinner : \(spinnerName) : { Index : \(index) - \(value) }")
            self.selectedState_id = "\(self.state_idArry[index])"
            selectedState = value
            self.getCityAPI()
        }
        if spinner == citySpinner { spinnerName = "citySpinner"
            selectedCity = value
            self.FilterProduct_API()
        }
      
    }
    

   
    @IBOutlet weak var silder: UISlider!
    @IBOutlet weak var lblPrice: UILabel!
    @IBOutlet weak var brandSpinner: LBZSpinner!
    @IBOutlet weak var stateSpinner: LBZSpinner!
    @IBOutlet weak var citySpinner: LBZSpinner!
    @IBOutlet weak var txtSearchProduct: UITextField!
    @IBOutlet weak var brandName: UILabel!
    @IBOutlet weak var stateName: UILabel!
    @IBOutlet weak var cityName: UILabel!
    @IBOutlet var firstImage: UIImageView!
    @IBOutlet var secondImage: UIImageView!
    @IBOutlet var thirdImage: UIImageView!
    @IBOutlet var forthImage: UIImageView!
    @IBOutlet var fifthImage: UIImageView!
    @IBOutlet var sixthImage: UIImageView!
    @IBOutlet var seventhImage: UIImageView!
    @IBOutlet var eighthImage: UIImageView!
    @IBOutlet var ninethImage: UIImageView!
    
    var getAllpothicData = [getAllopathicProducts]()
    var brand_name = NSArray()
    var states_name = NSArray()
    var city_name = NSArray()
    var state_idArry = NSArray()
    var selectedState_id = ""
    var sliderVal = ""
    var discountVal = ""
    var selectedBrand = ""
    var selectedState = ""
    var selectedCity = ""
    override func viewDidLoad(){
        super.viewDidLoad()
        self.navigationController?.isNavigationBarHidden = false
        txtSearchProduct.attributedPlaceholder = NSAttributedString(string:"Search Product", attributes: [NSAttributedStringKey.foregroundColor: UIColor.white])
        brandSpinner.delegate = self
        stateSpinner.delegate = self
        citySpinner.delegate = self
        if brandSpinner.selectedIndex == LBZSpinner.INDEX_NOTHING {
            print("NOTHING VALUE")
            brandSpinner.text = "Select Brand"
        }
        if stateSpinner.selectedIndex == LBZSpinner.INDEX_NOTHING {
            print("NOTHING VALUE")
            stateSpinner.text = "Select State"
        }
        if citySpinner.selectedIndex == LBZSpinner.INDEX_NOTHING {
            print("NOTHING VALUE")
            citySpinner.text = "Select City"
        }
        
        getBrandsAPI()
        getStatesAPI()
        // Do any additional setup after loading the view.
    }
    @IBAction func SliderValueChange(_ sender: UISlider) {
        self.lblPrice.text = String(format: "Price:      Rs. 10 - Rs. %i",Int(sender.value))
        sliderVal = "\(Int(sender.value))"
    }
    @IBAction func firstBtn(_ sender: UIButton){
        discountVal = "90"
        self.firstImage.image = #imageLiteral(resourceName: "select")
        self.secondImage.image = #imageLiteral(resourceName: "unselect")
        self.thirdImage.image = #imageLiteral(resourceName: "unselect")
        self.forthImage.image = #imageLiteral(resourceName: "unselect")
        self.fifthImage.image = #imageLiteral(resourceName: "unselect")
        self.sixthImage.image = #imageLiteral(resourceName: "unselect")
        self.seventhImage.image = #imageLiteral(resourceName: "unselect")
        self.eighthImage.image = #imageLiteral(resourceName: "unselect")
        self.ninethImage.image = #imageLiteral(resourceName: "unselect")
     }
    @IBAction func secondBtn(_ sender: UIButton){
        discountVal = "80"
        self.firstImage.image = #imageLiteral(resourceName: "unselect")
        self.secondImage.image = #imageLiteral(resourceName: "select")
        self.thirdImage.image = #imageLiteral(resourceName: "unselect")
        self.forthImage.image = #imageLiteral(resourceName: "unselect")
        self.fifthImage.image = #imageLiteral(resourceName: "unselect")
        self.sixthImage.image = #imageLiteral(resourceName: "unselect")
        self.seventhImage.image = #imageLiteral(resourceName: "unselect")
        self.eighthImage.image = #imageLiteral(resourceName: "unselect")
        self.ninethImage.image = #imageLiteral(resourceName: "unselect")
        
    }
    @IBAction func thirdBtn(_ sender: UIButton){
        discountVal = "70"
        self.thirdImage.image = #imageLiteral(resourceName: "select")
        self.secondImage.image = #imageLiteral(resourceName: "unselect")
        self.firstImage.image = #imageLiteral(resourceName: "unselect")
        self.forthImage.image = #imageLiteral(resourceName: "unselect")
        self.fifthImage.image = #imageLiteral(resourceName: "unselect")
        self.sixthImage.image = #imageLiteral(resourceName: "unselect")
        self.seventhImage.image = #imageLiteral(resourceName: "unselect")
        self.eighthImage.image = #imageLiteral(resourceName: "unselect")
        self.ninethImage.image = #imageLiteral(resourceName: "unselect")
        
    }
    @IBAction func forthBtn(_ sender: UIButton){
        discountVal = "60"
        self.forthImage.image = #imageLiteral(resourceName: "select")
        self.secondImage.image = #imageLiteral(resourceName: "unselect")
        self.thirdImage.image = #imageLiteral(resourceName: "unselect")
        self.firstImage.image = #imageLiteral(resourceName: "unselect")
        self.fifthImage.image = #imageLiteral(resourceName: "unselect")
        self.sixthImage.image = #imageLiteral(resourceName: "unselect")
        self.seventhImage.image = #imageLiteral(resourceName: "unselect")
        self.eighthImage.image = #imageLiteral(resourceName: "unselect")
        self.ninethImage.image = #imageLiteral(resourceName: "unselect")
        
    }
    
    @IBAction func fifthBtn(_ sender: UIButton){
        discountVal = "50"
        self.fifthImage.image = #imageLiteral(resourceName: "select")
        self.secondImage.image = #imageLiteral(resourceName: "unselect")
        self.thirdImage.image = #imageLiteral(resourceName: "unselect")
        self.forthImage.image = #imageLiteral(resourceName: "unselect")
        self.firstImage.image = #imageLiteral(resourceName: "unselect")
        self.sixthImage.image = #imageLiteral(resourceName: "unselect")
        self.seventhImage.image = #imageLiteral(resourceName: "unselect")
        self.eighthImage.image = #imageLiteral(resourceName: "unselect")
        self.ninethImage.image = #imageLiteral(resourceName: "unselect")
        
    }
    @IBAction func sixth(_ sender: UIButton){
        discountVal = "40"
        self.sixthImage.image = #imageLiteral(resourceName: "select")
        self.secondImage.image = #imageLiteral(resourceName: "unselect")
        self.thirdImage.image = #imageLiteral(resourceName: "unselect")
        self.forthImage.image = #imageLiteral(resourceName: "unselect")
        self.fifthImage.image = #imageLiteral(resourceName: "unselect")
        self.firstImage.image = #imageLiteral(resourceName: "unselect")
        self.seventhImage.image = #imageLiteral(resourceName: "unselect")
        self.eighthImage.image = #imageLiteral(resourceName: "unselect")
        self.ninethImage.image = #imageLiteral(resourceName: "unselect")
        
    }
    @IBAction func seventhBtn(_ sender: UIButton){
        discountVal = "30"
        self.seventhImage.image = #imageLiteral(resourceName: "select")
        self.secondImage.image = #imageLiteral(resourceName: "unselect")
        self.thirdImage.image = #imageLiteral(resourceName: "unselect")
        self.forthImage.image = #imageLiteral(resourceName: "unselect")
        self.fifthImage.image = #imageLiteral(resourceName: "unselect")
        self.sixthImage.image = #imageLiteral(resourceName: "unselect")
        self.firstImage.image = #imageLiteral(resourceName: "unselect")
        self.eighthImage.image = #imageLiteral(resourceName: "unselect")
        self.ninethImage.image = #imageLiteral(resourceName: "unselect")
    }
    
    @IBAction func eighthBtn(_ sender: UIButton){
        discountVal = "20"
        self.eighthImage.image = #imageLiteral(resourceName: "select")
        self.secondImage.image = #imageLiteral(resourceName: "unselect")
        self.thirdImage.image = #imageLiteral(resourceName: "unselect")
        self.forthImage.image = #imageLiteral(resourceName: "unselect")
        self.fifthImage.image = #imageLiteral(resourceName: "unselect")
        self.sixthImage.image = #imageLiteral(resourceName: "unselect")
        self.seventhImage.image = #imageLiteral(resourceName: "unselect")
        self.firstImage.image = #imageLiteral(resourceName: "unselect")
        self.ninethImage.image = #imageLiteral(resourceName: "unselect")
    }
    @IBAction func ninethBtn(_ sender: UIButton){
        discountVal = "10"
        self.ninethImage.image = #imageLiteral(resourceName: "select")
        self.secondImage.image = #imageLiteral(resourceName: "unselect")
        self.thirdImage.image = #imageLiteral(resourceName: "unselect")
        self.forthImage.image = #imageLiteral(resourceName: "unselect")
        self.fifthImage.image = #imageLiteral(resourceName: "unselect")
        self.sixthImage.image = #imageLiteral(resourceName: "unselect")
        self.seventhImage.image = #imageLiteral(resourceName: "unselect")
        self.eighthImage.image = #imageLiteral(resourceName: "unselect")
        self.firstImage.image = #imageLiteral(resourceName: "unselect")
    }
    
    
    func getBrandsAPI(){
        NetworkingService.shared.getData5(PostName: APIEndPoint.userCase.get_brands.caseValue) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.hideProgress()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            } else {
                self.brand_name = dic.value(forKeyPath: "record.brand_name") as! NSArray
                print(self.brand_name)
                self.brandSpinner.updateList(self.brand_name as! [String])
            }
        }
    }
    func getStatesAPI(){
        NetworkingService.shared.getData5(PostName: APIEndPoint.userCase.get_states.caseValue) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.hideProgress()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            } else {
                self.states_name = dic.value(forKeyPath: "record.state_name") as! NSArray
                self.state_idArry = dic.value(forKeyPath: "record.state_id") as! NSArray
                print(self.states_name, self.state_idArry)
                self.stateSpinner.updateList(self.states_name as! [String])
               
            }
        }
    }
    func getCityAPI(){
        let params = ["state_id":selectedState_id]
        NetworkingService.shared.getData3(PostName: APIEndPoint.userCase.get_cities.caseValue,parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.hideProgress()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            } else {
                self.city_name = dic.value(forKeyPath: "record.city_name") as! NSArray
                print(self.city_name)
                self.citySpinner.updateList(self.city_name as! [String])
            }
        }
    }
    @IBAction func selectCity(_ sender: UIButton) {
        let controller = UIAlertController(title: "Choose a City name", message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        controller.view.tintColor = UIColor.black
        let closure = { (action: UIAlertAction!) -> Void in
            let index = controller.actions.index(of: action)
            if index != nil {
                NSLog("Index: \(index!)")
                print(self.city_name[index!])
                self.cityName.text = (self.city_name[index!] as! String)
                //self.selectedState_id = (self.city_name[index!] as! String)
                
                
            }
        }
        for i in 0 ..< self.city_name.count { controller.addAction(UIAlertAction(title: (self.city_name[i] as! String), style: .default, handler: closure))
            // selected_Year = self.yearsArr[i] as? String
            
        }
        controller.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: nil))
        present(controller, animated: true, completion: nil)
    }
    @IBAction func selectStates(_ sender: UIButton) {
        let controller = UIAlertController(title: "Choose a State name", message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        controller.view.tintColor = UIColor.black
        let closure = { (action: UIAlertAction!) -> Void in
            let index = controller.actions.index(of: action)
            if index != nil {
                NSLog("Index: \(index!)")
                print(self.states_name[index!])
                self.stateName.text = (self.states_name[index!] as! String)
                self.selectedState_id = (self.state_idArry[index!] as! String)
                self.getCityAPI()
            }
        }
        for i in 0 ..< self.states_name.count { controller.addAction(UIAlertAction(title: (self.states_name[i] as! String), style: .default, handler: closure))
            // selected_Year = self.yearsArr[i] as? String
            
        }
        controller.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: nil))
        present(controller, animated: true, completion: nil)
    }
    @IBAction func selectBrands(_ sender: UIButton) {
        let controller = UIAlertController(title: "Choose a Brand name", message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        controller.view.tintColor = UIColor.black
        let closure = { (action: UIAlertAction!) -> Void in
            let index = controller.actions.index(of: action)
            if index != nil {
                NSLog("Index: \(index!)")
                print(self.brand_name[index!])
                self.brandName.text = (self.brand_name[index!] as! String)
                
            }
        }
        for i in 0 ..< self.brand_name.count { controller.addAction(UIAlertAction(title: (self.brand_name[i] as! String), style: .default, handler: closure))
            // selected_Year = self.yearsArr[i] as? String
            
        }
        controller.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: nil))
        present(controller, animated: true, completion: nil)
    }
    

    //MARK: FilterProduct_API
    func FilterProduct_API(){
//        self.addLoadingIndicator()
//        self.startAnim()
        let params = ["vendor_id": UserDefaults.standard.value(forKey: "USER_ID") as! String,
                      "cat_id": SingletonVariables.sharedInstace.cat_id,
                      "minPrice": sliderVal,
                      "maxPrice": "500",
                      "search": txtSearchProduct.text!,
                      "discount": discountVal,
                      "brand": selectedBrand,
                      "state":selectedState,
                      "city": selectedCity]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.search.caseValue,parameters: params) { (response) in
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
                    if data.count == 0{
                        self.stopAnim()
                        Utilities.ShowAlertView2(title: "Alert", message: "No Records Found!", viewController: self)
                    }else{
                        self.getAllpothicData = [getAllopathicProducts]()
                        for index in 0..<data.count
                        {
                            self.getAllpothicData.append(getAllopathicProducts(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((data[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((data[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((data[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((data[index] as AnyObject).value(forKey: "brand_name") ?? "")", min_quantity: "\((data[index] as AnyObject).value(forKey: "minquantity") ?? "")", product_status: "\((data[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                            
                        }
//                        self.dummyArry = [String]()
//                        for index1 in 0..<self.getAllpothicData.count{
//                            let a = self.getAllpothicData[index1].product_status
//                            if a == "already_added"{
//                                self.dummyArry.append("1")
//                            }else{
//                                self.dummyArry.append("0")
//                            }
//                        }
//                        self.stopAnim()
//                        UIView.transition(with: self.tableViewData,
//                                          duration: 0.35,
//                                          options: .transitionFlipFromLeft,
//                                          animations: { self.tableViewData.reloadData() })
                        
                        // self.tableViewData.reloadData()
                        
                    }
                }
            }
        }
    }
}
