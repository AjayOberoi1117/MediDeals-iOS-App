//
//  GetPostsResponse.swift
//  MVC-S
//
//  Created by Kyle Lee on 8/20/17.
//  Copyright © 2017 Kyle Lee. All rights reserved.
//

import Foundation
struct GetProfileResponse {
    
    var getdata = [getProfile]()
    
    init(json: Any) throws {
        guard let DataArray = json as? [String: Any] else { throw NetworkingError.someError }
        var l = [getProfile]()
        l = [getProfile(dict:DataArray)!]
        getdata = l
    }
    
    
}





