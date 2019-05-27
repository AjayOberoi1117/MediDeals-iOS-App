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
}
