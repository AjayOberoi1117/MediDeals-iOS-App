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
    
    @IBOutlet weak var AccTypeCollView: UICollectionView!
    fileprivate var sliderVc1: LIHSliderViewController!
    @IBOutlet weak var slider1Container: UIView!
    @IBOutlet weak var HomeTableView: UITableView!
    var checkSagueActon = ""
    var titleArry = [String]()
    var AddImagesArry = [UIImage]()
    var cell1 = HomeMenuCollectionViewCell1()
    var cell2 = HomeMenuCollectionViewCell2()
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
    var imagesArry = [UIImage]()
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideRightSideMenu()
        self.navigationController?.isNavigationBarHidden = false
        AddImagesArry = [#imageLiteral(resourceName: "image1"),#imageLiteral(resourceName: "image2"),#imageLiteral(resourceName: "image3")]
        titleName = ["Allopathic", "Ayurvedic", "FMCG","PCD/3rd Party","Surgical Goods","Generics"]
        self.imagesArry = [UIImage(named: "Allopathic"),UIImage(named: "ayurvedic"),UIImage(named: "customer (1)"),UIImage(named: "pharmacy"),UIImage(named: "Surgical"),UIImage(named: "generic")] as! [UIImage]
        titleArry = ["HOT DEALS","MOST DISCOUNTED","LATEST PRODUCTS"]
        let images: [UIImage] = [UIImage(named: "silder1")!,UIImage(named: "silder2")!,UIImage(named: "silder3")!]
        let slider1: LIHSlider = LIHSlider(images: images)
        
        self.sliderVc1  = LIHSliderViewController(slider: slider1)
        sliderVc1.delegate = self
        self.addChildViewController(self.sliderVc1)
        self.view.addSubview(self.sliderVc1.view)
        self.sliderVc1.didMove(toParentViewController: self)
      
        HomeTableView.cr.addHeadRefresh(animator: SlackLoadingAnimator()) { [weak self] in
            /// start refresh
            /// Do anything you want...
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                /// Stop refresh when your job finished, it will reset refresh footer if completion is true
                self?.HomeTableView.cr.endHeaderRefresh()
            })
        }
         HomeTableView.cr.beginHeaderRefresh()
    }
    @IBAction func cartReview(_ sender: UIBarButtonItem) {
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "Cart_ViewController") as! Cart_ViewController
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    @objc func methodOfReceivedNotification() {
        //self.deviceID_Api()
    }
    func itemPressedAtIndex(index: Int) {
        print("index \(index) is pressed")
    }
    
    override func viewDidLayoutSubviews() {
        
        self.sliderVc1!.view.frame = self.slider1Container.frame
    }

    override func viewWillAppear(_ animated: Bool) {
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
        
        // Register to receive notification
        NotificationCenter.default.addObserver(self, selector: #selector(Home_ViewController.methodOfReceivedNotification), name: NSNotification.Name(rawValue: "DEVICETOKEN_NOTI"), object: nil)
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
    
    func deviceID_Api(){
         self.addLoadingIndicator()
         self.startAnim()
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
            if let cell1 = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as? HomeMenuTableViewCell1 {
                cell1.lblTitle.text = titleArry[indexPath.row]
               // cell1.collectionViewFirst.tag = indexPath.row
                return cell1
            }
         return UITableViewCell()
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
        if section == 0 {
            return 4
        } else{
            return AddImagesArry.count
      }
        }
   
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == AccTypeCollView
        {}else{
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
        self.navigationController?.pushViewController(vc, animated: true)
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
                let newStringStrike = cell1.originalPrice.text
                let attributeString = NSMutableAttributedString(string: newStringStrike!)
                attributeString.addAttribute(NSAttributedStringKey.strikethroughStyle, value: 1, range: NSMakeRange(0, attributeString.length))
                cell1.originalPrice.attributedText = attributeString
                //          cell1.discountPercent.startBlink()
                return cell1
            }
        }
        return UICollectionViewCell()
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.section == 1{
        } else {
            cell1.discountPercent.startAnimation()
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

