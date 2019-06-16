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
class shippingAddressViewController: UIViewController ,LBZSpinnerDelegate,CLLocationManagerDelegate,UITextFieldDelegate {
    
    @IBOutlet weak var stateSpinner: LBZSpinner!
    @IBOutlet weak var citySpinner: LBZSpinner!
    @IBOutlet var countryName: UITextField!
    @IBOutlet weak var txtBusinessName: UITextField!
    @IBOutlet weak var txtEmail: UITextField!
    @IBOutlet weak var txtPhn: UITextField!
    @IBOutlet weak var txtPostalCode: UITextField!
    @IBOutlet weak var txtHouseNO: UITextField!
    @IBOutlet weak var street: UITextField!
    
    var locationManager = CLLocationManager()
    var lat = Float()
    var longi = Float()
    var states_name = NSArray()
    var city_name = NSArray()
    var state_idArry = NSArray()
    var selectedState_id = ""
    var selectedState = ""
    var selectedCity = ""
    func spinnerChoose(_ spinner: LBZSpinner, index: Int, value: String) {
         var spinnerName = ""
        if spinner == stateSpinner {
            print("Spinner : \(spinnerName) : { Index : \(index) - \(value) }")
            self.selectedState_id = "\(self.state_idArry[index])"
            if self.street.text == ""{
                Utilities.ShowAlertView2(title: "Alert", message: "Please enter Colony/Street/locality first", viewController: self)
            }else{
                    self.selectedState = value
                 self.getCityAPI()
            }
           
        }
        if spinner == citySpinner {
            spinnerName = "citySpinner"
            if selectedState == ""{
                Utilities.ShowAlertView2(title: "Alert", message: "Please choose state first", viewController: self)
            }else{
            self.selectedCity = value
            SingletonVariables.sharedInstace.ShippingAddress.updateValue("\(self.street.text! + "," + selectedCity + "," + selectedCity + "," + self.countryName.text!)" , forKey: "locality")
            SingletonVariables.sharedInstace.checkShippingAddress = "yes"
            }
        }
    }
  

    override func viewDidLoad() {
        super.viewDidLoad()
        txtPhn.delegate = self
        txtEmail.delegate = self
        txtHouseNO.delegate = self
        txtPostalCode.delegate = self
        txtBusinessName.delegate = self
        txtBusinessName.becomeFirstResponder()
        street.delegate = self
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
        
        print(SingletonVariables.sharedInstace.userProfileData)
        txtPhn.text = "+91- " + (SingletonVariables.sharedInstace.userProfileData.value(forKey: "contact_no") as! String)
        txtEmail.text = (SingletonVariables.sharedInstace.userProfileData.value(forKey: "email") as! String)
        
        txtBusinessName.text = (SingletonVariables.sharedInstace.userProfileData.value(forKey: "firm_name") as! String)
        
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
    
func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
    if textField == self.txtBusinessName{
       
     }
    else if textField == self.txtEmail{
        if self.txtBusinessName.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter business name first", viewController: self)
        }else{
        
            //SingletonVariables.sharedInstace.ShippingAddress.updateValue(UserDefaults.standard.value(forKey: "USER_ID") as! String, forKey: "user_id")
            SingletonVariables.sharedInstace.ShippingAddress.updateValue(self.txtBusinessName.text!, forKey: "firm_name")
        }
    }
    else if textField == self.txtPhn{
        if self.txtEmail.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter email first", viewController: self)
        }else{
            if (isValidEmail(testStr: self.txtEmail.text!) == false)
            {
                Utilities.ShowAlertView2(title: "Alert", message: "Please enter valid email", viewController: self)
            }else{
                
                let length = (txtPhn.text?.count)! - range.length + string.count
                print("lenght",length)
                if length == 1{
                    let num : String = self.formatNumber(mobileNo: txtPhn.text!)
                    txtPhn.text = "+91- " + num
                }
                SingletonVariables.sharedInstace.ShippingAddress.updateValue(self.txtEmail.text!, forKey: "email")
            }
        }
    }
    else if textField == self.txtPostalCode{
        if self.txtPhn.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter Phone number first", viewController: self)
        }else{
             SingletonVariables.sharedInstace.ShippingAddress.updateValue(self.txtPhn.text!, forKey: "contact_no")
         }
    }
    else if textField == self.txtHouseNO{
        if self.txtPostalCode.text == ""{
            Utilities.ShowAlertView2(title: "Alert", message: "Please enter Postal code first", viewController: self)
        }else{
            if txtPostalCode.text!.count < 6 ||  txtPostalCode.text!.count > 6{
                Utilities.ShowAlertView2(title: "Alert", message: "Please enter six digits postal code", viewController: self)
            }else{
                SingletonVariables.sharedInstace.ShippingAddress.updateValue(self.txtPostalCode.text!, forKey: "post_code")
            }
            
        }
    }
    else if textField == self.street{
        
    }
   
    return true
    }
    
    func formatNumber(mobileNo: String) -> String{
        var str : NSString = mobileNo as NSString
        str = str.replacingOccurrences(of: "+91- ", with: "") as NSString
        return str as String
    }
    
    func isValidEmail(testStr:String) -> Bool
    {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        
        return emailTest.evaluate(with: testStr)
        
    }
}
