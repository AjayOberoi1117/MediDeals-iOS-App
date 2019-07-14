//
//  GlobalVariables.swift
//  OSODCompany
//
//  Created by SIERRA on 8/7/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import Foundation
import UIKit

class SingletonVariables: NSObject {
    //MARK: Singleton Object Creation 
    static let sharedInstace: SingletonVariables = {
        
        let singletonObject = SingletonVariables()
        return singletonObject
    }()
    var userProfileData = NSDictionary()
    var userId = ""
    var loginStatus = ""
    var accountType = ""
    var AccountCategory = ""
    var cat_id = ""
    var checkShippingAddress = ""
    var ShippingAddress = ["user_id": "",
                           "firm_name": "",
                           "email": "",
                           "contact_no": "",
                           "post_code": "",
                           "house_no": "",
                           "locality": "",
                           "payment_type":"cashOnDelivery",
                           "tranx_id": ""]
    var FilterDic = ["vendor_id": "",
                     "cat_id": "",
                     "minPrice": "",
                     "maxPrice": "500",
                     "search": "",
                     "discount": "",
                     "brand": "",
                     "state":"",
                     "city": ""]
    
    var categoryDic = [["cat_name":"ALLOPATHIC","cat_id":"1"],
                       ["cat_name":"AYURVEDIC","cat_id":"2"],
                       ["cat_name":"FMCG","cat_id":"3"],
                       ["cat_name":"PCD COMPANIES/3RD PARTY","cat_id":"4"],
                       ["cat_name":"SURGICAL GOODS","cat_id":"5"]]
}
