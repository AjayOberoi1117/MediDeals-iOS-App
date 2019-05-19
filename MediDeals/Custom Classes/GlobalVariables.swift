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
    
    var _jobId = NSNumber()
    var cat_id = ""
    
}
