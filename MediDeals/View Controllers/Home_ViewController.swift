//
//  Home_ViewController.swift
//  MediDeals
//
//  Created by Pankaj Rana on 30/12/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit
import LIHImageSlider
import MapKit
import CRRefresh
@available(iOS 11.0, *)
class Home_ViewController: UIViewController,LIHSliderDelegate,CLLocationManagerDelegate{
    @IBOutlet weak var lblTxt: UILabel!
    @IBOutlet weak var AccTypeCollView: UICollectionView!
    fileprivate var sliderVc1: LIHSliderViewController!
    @IBOutlet weak var slider1Container: UIView!
    @IBOutlet weak var HomeTableView: UITableView!
    var getProfileData = [getProfile]()
    var checkSagueActon = String()
    var titleArry = [String]()
    var AddImagesArry = [UIImage]()
    var tableCell = HomeMenuTableViewCell1()
    var cell1 = HomeMenuCollectionViewCell1()
    var cell2 = HomeMenuCollectionViewCell2()
    var getHotDealsData = [getHomeProducts]()
    var getMostDiscountedData = [getHomeProducts]()
    var getNewProductsData = [getHomeProducts]()
    var dummyHotDealsArry = [String]()
    var dummyMostDiscountedArry = [String]()
    var dummyNewProductsArry = [String]()
    var locationManager = CLLocationManager()
    var lat = Float()
    var longi = Float()
    var latitude = Float()
    var longitude = Float()
    var addressString : String = ""
    var currentLat = CLLocationDegrees()
    var currentLong = CLLocationDegrees()
    var DEVICETOKEN : String!
    var timeZoneVal : String!
    var timeZone = NSTimeZone()
    var latArray = NSArray()
    var lngArray = NSArray()
    var titleName = [String]()
    var titleCat = [String]()
    var imagesArry = [UIImage]()
    var tagVal = Int()
    var buttonTapped:((HomeMenuCollectionViewCell1) -> Void)? = nil
    
    var btnBarBadge : MJBadgeBarButton!
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Medideals"
        Utilities.HideRightSideMenu()
        self.navigationController?.isNavigationBarHidden = false
        AddImagesArry = [#imageLiteral(resourceName: "image1"),#imageLiteral(resourceName: "image2"),#imageLiteral(resourceName: "image3")]
        titleName = ["Allopathic", "Ayurvedic", "FMCG","PCD/3rd Party","Surgical Goods","Generics"]
        titleCat = ["1", "2", "3","4","5","6"]
        self.imagesArry = [UIImage(named: "Allopathic"),UIImage(named: "ayurvedic"),UIImage(named: "customer (1)"),UIImage(named: "pharmacy"),UIImage(named: "Surgical"),UIImage(named: "generic")] as! [UIImage]
        titleArry = ["HOT DEALS","MOST DISCOUNTED","LATEST PRODUCTS"]
        let images: [UIImage] = [UIImage(named: "silder1")!,UIImage(named: "silder2")!,UIImage(named: "silder3")!]
        let slider1: LIHSlider = LIHSlider(images: images)
        
        self.sliderVc1  = LIHSliderViewController(slider: slider1)
        sliderVc1.delegate = self
        self.addChildViewController(self.sliderVc1)
        self.view.addSubview(self.sliderVc1.view)
        self.sliderVc1.didMove(toParentViewController: self)
        
        self.lblTxt.startAnimation()
       
        
        if UserDefaults.standard.value(forKey: "USER_ID") != nil{
            self.getProfileAPI()
            self.deviceID_Api()
        }
        
        self.HomeTableView.cr.addHeadRefresh(animator: SlackLoadingAnimator()) { [weak self] in
            // start refresh
            // Do anything you want...
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                            /// Stop refresh when your job finished, it will reset refresh footer if completion is true
                            self?.HomeTableView.cr.endHeaderRefresh()
                        })
        }
        
         cartbtn()
        
         self.getHomeData_Api()
       // HomeTableView.cr.beginHeaderRefresh()
        
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
    func deviceID_Api(){
        //        self.addLoadingIndicator()
        //        self.startAnim()
        let params = [ "vendor_id" : UserDefaults.standard.value(forKey: "USER_ID") as! String,
                       "device_type": "I",
                       "device_id":UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String]
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.update_device_id.caseValue, parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            }
            else
            {
                self.stopAnim()
            }
            
        }
    }
    @IBAction func cartReview(_ sender: MJBadgeBarButton) {
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "Cart_ViewController") as! Cart_ViewController
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    func itemPressedAtIndex(index: Int) {
        print("index \(index) is pressed")
    }
    
    override func viewDidLayoutSubviews() {
        
        self.sliderVc1!.view.frame = self.slider1Container.frame
    }

    override func viewWillAppear(_ animated: Bool) {
        self.getCartApi()
        if checkSagueActon == "yes"{
            Utilities.AttachSideMenuController()
            checkSagueActon = ""
        }else{
           
        }
        // User Location delegate for google Map
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.startUpdatingLocation()
        
        
    }
    
    @IBAction func buyNow(_ sender: UIButton) {
        
    }
    
    
    
    func initTimeZone() {
        timeZone = NSTimeZone.local as NSTimeZone
        timeZoneVal = timeZone.name
        print(timeZoneVal)
    }
    
    //MARK: Call to Location Manager Delegates to check authorization status
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            // If status has not yet been determied, ask for authorization
            manager.requestWhenInUseAuthorization()
            manager.desiredAccuracy = kCLLocationAccuracyBest
            
            break
        case .authorizedWhenInUse:
            // If authorized when in use
            manager.startUpdatingLocation()
            break
        case .authorizedAlways:
            // If always authorized
            
            break
        case .restricted:
            // If restricted by e.g. parental controls. User can't enable Location Services
            let alert = UIAlertController(title: "Location Services Disabled", message: "Please enable Location Services in Settings", preferredStyle: .alert)
            
            let okAction = UIAlertAction(title: "Settings", style: .default, handler: {(alert: UIAlertAction!) in
                UIApplication.shared.open(URL(string:UIApplicationOpenSettingsURLString)!)
            })
            let CancelAction = UIAlertAction(title: "Cancel", style: .default, handler: nil)
            alert.addAction(okAction)
            alert.addAction(CancelAction)
            present(alert, animated: true, completion: nil)
            break
        case .denied:
            // If user denied your app access to Location Services, but can grant access from Settings.app
            let alert = UIAlertController(title: "Location Services Disabled", message: "Please enable Location Services in Settings", preferredStyle: .alert)
            
            let okAction = UIAlertAction(title: "Settings", style: .default, handler: {(alert: UIAlertAction!) in
                UIApplication.shared.open(URL(string:UIApplicationOpenSettingsURLString)!)
            })
            let CancelAction = UIAlertAction(title: "Cancel", style: .default, handler: nil)
            alert.addAction(okAction)
            alert.addAction(CancelAction)
            present(alert, animated: true, completion: nil)
            break
            
        default:
            break
        }
    }
    
    //MARK: To update User Location in Google Map:
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("---  delegate are call --- > ---- > --- >")
        
        if let location = locations.last {
            
           // let center = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            //            let camera = GMSCameraPosition.camera(withLatitude:CLLocationDegrees(currentLat), longitude: CLLocationDegrees(currentLong), zoom: 10);
//            self.mapView_outlet.camera = camera
            
            //print("Latitude :- \(location.coordinate.latitude)")
            //print("Longitude :-\(location.coordinate.longitude)")
            // marker.map = self.mapview
            
            currentLat = Double(location.coordinate.latitude)
            currentLong = Double(location.coordinate.longitude)
//            mapView_outlet.isMyLocationEnabled = true
//            mapView_outlet.settings.myLocationButton = true
//            self.getAddressFromLatLon(pdblLatitude: "\(self.currentLat)", withLongitude:"\(self.currentLong)")
            self.locationManager.stopUpdatingLocation()
            // self.setMarker(poistion: center)
           // updateLocationApi()
        }
    }
    //To Handle failure case in google map
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error while updating location " + error.localizedDescription)
    }
    
    @IBAction func menuAct(_ sender: UIBarButtonItem) {
        Utilities.LeftSideMenu()
    }
    
    //MARK: Update location Api:
    func updateLocationApi(){
       // self.showProgress()
//          self.startAnim()
        let params = [ "vendor_id" : UserDefaults.standard.value(forKey: "USER_ID") as! String,
                       "latitude": "\(currentLat)",
                       "longitude":"\(currentLong)"]
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.update_lat_long.caseValue, parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.hideProgress()
                //self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            }
            else
            {
                //self.stopAnim()
                self.hideProgress()
            }
            
        }
    }
    
    
    func getHomeData_Api(){
        HomeTableView.cr.beginHeaderRefresh()
        let params = ["device_id": UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String]
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.home.caseValue, parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            }
            else
            {
                self.stopAnim()
                self.getHotDealsData = [getHomeProducts]()
                self.getMostDiscountedData = [getHomeProducts]()
                self.getNewProductsData = [getHomeProducts]()
                self.dummyHotDealsArry = [String]()
                self.dummyNewProductsArry = [String]()
                self.dummyMostDiscountedArry = [String]()
                // get hot deals Arrays ...
                if let data = (dic.value(forKey: "hotDealsProducts") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    for index in 0..<data.count-4
                    {
                        self.getHotDealsData.append(getHomeProducts(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((data[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((data[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((data[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((data[index] as AnyObject).value(forKey: "barnd_name") ?? "")", min_quantity: "\((data[index] as AnyObject).value(forKey: "minquantity") ?? "")", product_status: "\((data[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                        
                        if (data[index] as AnyObject).value(forKey: "product_status") as! String == "already_added"{
                            self.dummyHotDealsArry.append("1")
                        }else{
                            self.dummyHotDealsArry.append("0")
                        }
                     }
                }
                
                // get Most Discounted Arrays ...
                if let data = (dic.value(forKey: "getMostDiscounted") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    for index in 0..<data.count-4
                    {
                        self.getMostDiscountedData.append(getHomeProducts(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((data[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((data[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((data[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((data[index] as AnyObject).value(forKey: "barnd_name") ?? "")", min_quantity: "\((data[index] as AnyObject).value(forKey: "minquantity") ?? "")", product_status: "\((data[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                        
                        if (data[index] as AnyObject).value(forKey: "product_status") as! String == "already_added"{
                            self.dummyMostDiscountedArry.append("1")
                        }else{
                            self.dummyMostDiscountedArry.append("0")
                        }
                    }
                }
                
                // get new products Arrays ...
                if let data = (dic.value(forKey: "getNewProducts") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    for index in 0..<data.count-4
                    {
                        self.getNewProductsData.append(getHomeProducts(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((data[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((data[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((data[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((data[index] as AnyObject).value(forKey: "barnd_name") ?? "")", min_quantity: "\((data[index] as AnyObject).value(forKey: "minquantity") ?? "")", product_status: "\((data[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                        
                        if (data[index] as AnyObject).value(forKey: "product_status") as! String == "already_added"{
                            self.dummyNewProductsArry.append("1")
                        }else{
                            self.dummyNewProductsArry.append("0")
                        }
                    }
                }
                
                print(self.dummyHotDealsArry,self.dummyMostDiscountedArry,self.dummyNewProductsArry)
                
//                UIView.transition(with: self.HomeTableView,
//                                  duration: 0.35,
//                                  options: .transitionFlipFromLeft,
//                                  animations: { self.HomeTableView.reloadData() })
                
                 self.HomeTableView.reloadData()
               
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                    /// Stop refresh when your job finished, it will reset refresh footer if completion is true
                    self.HomeTableView.cr.endHeaderRefresh()
                })
                
            }
            
        }
    }
    
    func getHomeData_Api1(){
        //HomeTableView.cr.beginHeaderRefresh()
        let params = ["device_id": UserDefaults.standard.value(forKey: "DEVICETOKEN") as! String]
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.home.caseValue, parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            }
            else
            {
                self.stopAnim()
                self.getHotDealsData = [getHomeProducts]()
                self.getMostDiscountedData = [getHomeProducts]()
                self.getNewProductsData = [getHomeProducts]()
                
                // get hot deals Arrays ...
                if let data = (dic.value(forKey: "hotDealsProducts") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    for index in 0..<data.count-4
                    {
                        self.getHotDealsData.append(getHomeProducts(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((data[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((data[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((data[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((data[index] as AnyObject).value(forKey: "barnd_name") ?? "")", min_quantity: "\((data[index] as AnyObject).value(forKey: "minquantity") ?? "")", product_status: "\((data[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                    }
                }
                
                // get Most Discounted Arrays ...
                if let data = (dic.value(forKey: "getMostDiscounted") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    for index in 0..<data.count-4
                    {
                        self.getMostDiscountedData.append(getHomeProducts(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((data[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((data[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((data[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((data[index] as AnyObject).value(forKey: "barnd_name") ?? "")", min_quantity: "\((data[index] as AnyObject).value(forKey: "minquantity") ?? "")", product_status: "\((data[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                    }
                }
                
                // get new products Arrays ...
                if let data = (dic.value(forKey: "getNewProducts") as? NSArray)?.mutableCopy() as? NSMutableArray
                {
                    for index in 0..<data.count-4
                    {
                        self.getNewProductsData.append(getHomeProducts(product_id: "\((data[index] as AnyObject).value(forKey: "product_id") ?? "")", title:"\((data[index] as AnyObject).value(forKey: "title") ?? "")", old_price: "\((data[index] as AnyObject).value(forKey: "old_price") ?? "")", price: "\((data[index] as AnyObject).value(forKey: "price") ?? "")", discount: "\((data[index] as AnyObject).value(forKey: "discount") ?? "")", code: "\((data[index] as AnyObject).value(forKey: "code") ?? "")", brandName: "\((data[index] as AnyObject).value(forKey: "barnd_name") ?? "")", min_quantity: "\((data[index] as AnyObject).value(forKey: "minquantity") ?? "")", product_status: "\((data[index] as AnyObject).value(forKey: "product_status") ?? "")"))
                    }
                }
                
                
                
                //                UIView.transition(with: self.HomeTableView,
                //                                  duration: 0.35,
                //                                  options: .transitionFlipFromLeft,
                //                                  animations: { self.HomeTableView.reloadData() })
                
                self.HomeTableView.reloadData()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                    /// Stop refresh when your job finished, it will reset refresh footer if completion is true
                    self.HomeTableView.cr.endHeaderRefresh()
                })
                
            }
            
        }
    }
    
    func getProfileAPI(){
        let params = [ "vendor_id": UserDefaults.standard.value(forKey: "USER_ID") as! String,
        ]
        print(params)
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.getProfile.caseValue, parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.hideProgress()
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            }
            else
            {
                self.hideProgress()
                self.stopAnim()
                
                let records = dic.value(forKey: "record") as! NSDictionary
                 SingletonVariables.sharedInstace.userProfileData = records
                let number = records.value(forKey: "contact_no") as! String
                let email = records.value(forKey: "email") as! String
                    UserDefaults.standard.set(email, forKey: "PROFILE_EMAIL")
                    UserDefaults.standard.set(number, forKey: "PROFILE_NAME")
                
            }
            
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
    @IBAction func BuyNowBtn(_ sender: UIButton) {
        var superview = sender.superview
        while let view = superview, !(view is UITableViewCell) {
            superview = view.superview
        }
        guard let cell = superview as? UITableViewCell else {
            print("button is not contained in a table view cell")
            return
        }
        guard let indexPath = HomeTableView.indexPath(for: cell) else {
            print("failed to get index path for cell containing button")
            return
        }
        // We've got the index path for the cell that contains the button, now do something with it.
        print("button is in row \(indexPath.row)")
        
        if indexPath.row == 0 {
             print(self.getHotDealsData[sender.tag].product_id)
            if self.dummyHotDealsArry[sender.tag] == "0"{
                self.dummyHotDealsArry[sender.tag] = "1"
                addtoCartApi(productid: self.getHotDealsData[sender.tag].product_id, quantity: self.getHotDealsData[sender.tag].min_quantity)
              }else{
                performPushSeguefromController(identifier: "Cart_ViewController")
            }
        }else if indexPath.row == 1 {
            print(self.getMostDiscountedData[sender.tag].product_id)
            if self.dummyMostDiscountedArry[sender.tag] == "0"{
                 self.dummyMostDiscountedArry[sender.tag] = "1"
                addtoCartApi(productid: self.getMostDiscountedData[sender.tag].product_id, quantity: self.getMostDiscountedData[sender.tag].min_quantity)
               
            }else{
                performPushSeguefromController(identifier: "Cart_ViewController")
            }
        }else if indexPath.row == 2 {
            print(self.getNewProductsData[sender.tag].product_id)
            if self.dummyNewProductsArry[sender.tag] == "0"{
                self.dummyNewProductsArry[sender.tag] = "1"
                addtoCartApi(productid: self.getNewProductsData[sender.tag].product_id, quantity: self.getNewProductsData[sender.tag].min_quantity)
                
            }else{
                performPushSeguefromController(identifier: "Cart_ViewController")
            }
        }else{
            
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
                self.getCartApi()
                self.HomeTableView.reloadData()
            }
        }
    }
    
}

@available(iOS 11.0, *)
extension Home_ViewController : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
         return titleArry.count
       }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        tableCell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! HomeMenuTableViewCell1
        tableCell.lblTitle.text = titleArry[indexPath.row]
        self.HomeTableView.tag = indexPath.row
        
        tableCell.collectionViewFirst.tag = indexPath.row
        self.tagVal = tableCell.collectionViewFirst.tag
        tableCell.collectionViewFirst.reloadData()
        return tableCell
        
    }
    
//    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        let vc = self.storyboard?.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
//        self.navigationController?.pushViewController(vc, animated: true)
//    }
    
}
@available(iOS 11.0, *)
extension Home_ViewController : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout
{
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if collectionView == AccTypeCollView{
             return 1
        }else{
            return 2
        }
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == AccTypeCollView{
            return titleName.count
        }else{
            if self.getHotDealsData.count != 0{
                if section == 0 {
                    if tagVal == 0 {
                        return self.getHotDealsData.count
                    }else if tagVal == 1 {
                        return self.getMostDiscountedData.count
                    }else if tagVal == 2 {
                        return self.getNewProductsData.count
                    }else{
                        return 4
                    }
                    
                } else{
                    return AddImagesArry.count
                }
            }else{
                return 0
            }
        }
        
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == AccTypeCollView
        {
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath as IndexPath) as? AccTypeCollectionViewCell
            {
                cell.lblName.text = titleName[indexPath.row]
                cell.imageAcc.image = imagesArry[indexPath.row]
                return cell
            }
        }else{
            if indexPath.section == 1{
                cell2 = collectionView.dequeueReusableCell(withReuseIdentifier: "cell2", for: indexPath as IndexPath) as! HomeMenuCollectionViewCell2
                cell2.AddImages.image = AddImagesArry[indexPath.row]
                return cell2
                
            } else {
                cell1 = collectionView.dequeueReusableCell(withReuseIdentifier: "cell1", for: indexPath as IndexPath) as! HomeMenuCollectionViewCell1
               

                
                if tagVal == 0{
                    cell1.titleName.text = self.getHotDealsData[indexPath.row].title
                    cell1.brandName.text = self.getHotDealsData[indexPath.row].brandName
                    cell1.discountPrice.text = "Rs " + self.getHotDealsData[indexPath.row].price
                    let newStringStrike =  "Rs " + self.getHotDealsData[indexPath.row].old_price
                    let attributeString = NSMutableAttributedString(string: newStringStrike)
                    attributeString.addAttribute(NSAttributedStringKey.strikethroughStyle, value: 1, range: NSMakeRange(0, attributeString.length))
                    cell1.originalPrice.attributedText = attributeString
                    let d = Float(self.getHotDealsData[indexPath.row].discount)!.rounded(.towardZero)
                    print("discount value is" , d)
                    // cell1.discountPercent.startAnimation()
                    cell1.discountPercent.text = String(format: "%.0f" , d) + "%"
                    cell1.buyNowBtn.tag = indexPath.row
                    let product_status = self.dummyHotDealsArry[indexPath.row]
                    if product_status == "1"{
                        cell1.buyNowBtn.backgroundColor = BUTTONSELECTION_COLOR
                        cell1.buyNowBtn.setTitle("GO TO CART", for: .normal)
                    }else{
                        cell1.buyNowBtn.backgroundColor = BUTTON_COLOR
                        cell1.buyNowBtn.setTitle("BUY NOW", for: .normal)
                    }
                    

                }else if tagVal == 1 {
                    cell1.titleName.text = self.getMostDiscountedData[indexPath.row].title
                    cell1.brandName.text = self.getMostDiscountedData[indexPath.row].brandName
                    cell1.discountPrice.text = "Rs " + self.getMostDiscountedData[indexPath.row].price
                    let newStringStrike =  "Rs " + self.getMostDiscountedData[indexPath.row].old_price
                    let attributeString = NSMutableAttributedString(string: newStringStrike)
                    attributeString.addAttribute(NSAttributedStringKey.strikethroughStyle, value: 1, range: NSMakeRange(0, attributeString.length))
                    cell1.originalPrice.attributedText = attributeString
                    let d = Float(self.getMostDiscountedData[indexPath.row].discount)!.rounded(.towardZero)
                    print("discount value is" , d)
                    // cell1.discountPercent.startAnimation()
                    cell1.discountPercent.text = String(format: "%.0f" , d) + "%"
                    
                    cell1.buyNowBtn.tag = indexPath.row
                    let product_status = self.dummyMostDiscountedArry[indexPath.row]
                    if product_status == "1"{
                        cell1.buyNowBtn.backgroundColor = BUTTONSELECTION_COLOR
                        cell1.buyNowBtn.setTitle("GO TO CART", for: .normal)
                    }else{
                        cell1.buyNowBtn.backgroundColor = BUTTON_COLOR
                        cell1.buyNowBtn.setTitle("BUY NOW", for: .normal)
                    }
                    
                }else if tagVal == 2 {
                    cell1.titleName.text = self.getNewProductsData[indexPath.row].title
                    cell1.brandName.text = self.getNewProductsData[indexPath.row].brandName
                    cell1.discountPrice.text = "Rs " + self.getNewProductsData[indexPath.row].price
                    let newStringStrike =  "Rs " + self.getNewProductsData[indexPath.row].old_price
                    let attributeString = NSMutableAttributedString(string: newStringStrike)
                    attributeString.addAttribute(NSAttributedStringKey.strikethroughStyle, value: 1, range: NSMakeRange(0, attributeString.length))
                    cell1.originalPrice.attributedText = attributeString
                    let d = Float(self.getNewProductsData[indexPath.row].discount)!.rounded(.towardZero)
                    print("discount value is" , d)
                    // cell1.discountPercent.startAnimation()
                    cell1.discountPercent.text = String(format: "%.0f" , d) + "%"
                    cell1.buyNowBtn.tag = indexPath.row
                    let product_status = self.dummyNewProductsArry[indexPath.row]
                    if product_status == "1"{
                        cell1.buyNowBtn.backgroundColor = BUTTONSELECTION_COLOR
                        cell1.buyNowBtn.setTitle("GO TO CART", for: .normal)
                    }else{
                        cell1.buyNowBtn.backgroundColor = BUTTON_COLOR
                        cell1.buyNowBtn.setTitle("BUY NOW", for: .normal)
                    }
                }
                
                return cell1
            }
        }
        return UICollectionViewCell()
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == AccTypeCollView
        {
            let vc = self.storyboard?.instantiateViewController(withIdentifier: "MenuViewController") as! MenuViewController
            vc.titleName = self.titleName[indexPath.row]
            vc.catID = self.titleCat[indexPath.row]
            
            self.navigationController?.pushViewController(vc, animated: true)
        }else{
            //print(modelPurchase[collectionView.tag].listFlowPosition[indexPath.item])
            if indexPath.section == 0 {
                if collectionView.tag == 0 {
                    let vc = self.storyboard?.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
                    vc.isComeFrom = "home"
                    vc.selectedProductID = self.getHotDealsData[indexPath.row].product_id
                    self.navigationController?.pushViewController(vc, animated: true)
                }else if collectionView.tag == 1 {
                    let vc = self.storyboard?.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
                    vc.isComeFrom = "home"
                    vc.selectedProductID = self.getMostDiscountedData[indexPath.row].product_id
                    self.navigationController?.pushViewController(vc, animated: true)
                }else if collectionView.tag == 2 {
                    let vc = self.storyboard?.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
                    vc.isComeFrom = "home"
                    vc.selectedProductID = self.getNewProductsData[indexPath.row].product_id
                    self.navigationController?.pushViewController(vc, animated: true)
                }else{
                    
                }
                
            }
            
        }
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.section == 1{
        } else {
            if self.getHotDealsData.count != 0{
                cell1.discountPercent.startAnimation()
            }
          }
    }
   func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    if collectionView == AccTypeCollView
    {
        return CGSize(width:(AccTypeCollView.frame.width)/6-10, height: 70)
    }else{
        if indexPath.section == 1{
            return CGSize(width:(collectionView.frame.width)/3-10, height: 160)
        }else{
            return CGSize(width:(collectionView.frame.width)/2-5, height: 160)
        }
    }
    }
}

