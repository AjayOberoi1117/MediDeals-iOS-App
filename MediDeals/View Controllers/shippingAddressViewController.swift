//
//  shippingAddressViewController.swift
//  MediDeals
//
//  Created by SIERRA on 2/12/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit
import MapKit
@available(iOS 11.0, *)
class shippingAddressViewController: UIViewController ,LBZSpinnerDelegate,CLLocationManagerDelegate {
    
    @IBOutlet weak var stateSpinner: LBZSpinner!
    @IBOutlet weak var citySpinner: LBZSpinner!
    @IBOutlet var countryName: UITextField!
   
    var locationManager = CLLocationManager()
    var lat = Float()
    var longi = Float()
    var states_name = NSArray()
    var city_name = NSArray()
    var state_idArry = NSArray()
    var selectedState_id = ""
    
    func spinnerChoose(_ spinner: LBZSpinner, index: Int, value: String) {
         var spinnerName = ""
        if spinner == stateSpinner {
            print("Spinner : \(spinnerName) : { Index : \(index) - \(value) }")
            self.selectedState_id = "\(self.state_idArry[index])"
            self.getCityAPI()
        }
        if spinner == citySpinner { spinnerName = "citySpinner" }
    }
  

    override func viewDidLoad() {
        super.viewDidLoad()
        stateSpinner.delegate = self
        citySpinner.delegate = self
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        if stateSpinner.selectedIndex == LBZSpinner.INDEX_NOTHING {
            print("NOTHING VALUE")
            stateSpinner.text = "Select State"
        }
        if citySpinner.selectedIndex == LBZSpinner.INDEX_NOTHING {
            print("NOTHING VALUE")
            citySpinner.text = "Select City"
        }
         getStatesAPI()

        // Do any additional setup after loading the view.
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
    // MARK: USER CUURENT LOCATION
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    {
        let userLocation = locations.last
        let center = CLLocationCoordinate2D(latitude: userLocation!.coordinate.latitude, longitude: userLocation!.coordinate.longitude)
        print(center)
        
        print("Latitude :- \(userLocation!.coordinate.latitude)")
        print("Longitude :-\(userLocation!.coordinate.longitude)")
        
        lat = Float(Double(userLocation!.coordinate.latitude))
        longi = Float(Double(userLocation!.coordinate.longitude))
        
        
        locationManager.stopUpdatingLocation()
        
        
        lat = Float(Double(userLocation!.coordinate.latitude))
        longi = Float(Double(userLocation!.coordinate.longitude))
        
        self.getAddressFromLatLong(latitude: lat, longitude: longi)
        
        
    }
    
    //MARK: Function to get User Address:
    
    func getAddressFromLatLong(latitude:Float, longitude:Float){
        
        let ceo: CLGeocoder = CLGeocoder()
        var center : CLLocationCoordinate2D = CLLocationCoordinate2D()
        center.latitude = CLLocationDegrees(latitude)
        center.longitude = CLLocationDegrees(longitude)
        
        let loc: CLLocation = CLLocation(latitude:center.latitude, longitude: center.longitude)
        ceo.reverseGeocodeLocation(loc, completionHandler:
            {(placemarks, error) in
                if (error != nil)
                {
                    print("reverse geodcode fail: \(error!.localizedDescription)")
                }
                let pm = placemarks! as [CLPlacemark]
                
                if pm.count > 0 {
                    let pm = placemarks![0]
                    print(pm.country as Any)
                    print(pm.locality as Any)
                    print(pm.subLocality as Any)
                    print(pm.thoroughfare as Any)
                    print(pm.postalCode as Any)
                    print(pm.subThoroughfare as Any)
                    print(pm.isoCountryCode as Any)
                    self.countryName.text = (pm.country as! String)
                }
                
                
        })
        
    }
    //To Handle failure case in google map
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error while updating location " + error.localizedDescription)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
