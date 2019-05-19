//
//  Post.swift
//  MVC-S
//
//  Created by Kyle Lee on 8/20/17.
//  Copyright © 2017 Kyle Lee. All rights reserved.
//
import Foundation

struct SignUp
{
    let Id: String
    let username: String
    init?(dict:[String: Any])
    {
        print(dict)
        guard let Id = dict["id"] as? String,
            let username = dict["username"] as? String
            else { return nil }
        self.Id = Id
        self.username = username
    }
}
struct ErrorResponse
{
    let message: String
    init?(dict:[String: Any]) {
        print(dict)
        guard let message = dict["message"] as? String
            else { return nil }
        self.message = message
   }
}

struct getProfile
{
    let contact_no: String
    let drug_licence: String
    let email: String
    let firm_address:  String
    let firm_name: String
    let fssai_no: String
    let user_type: String
    let vendor_id: String
    let website_url: String
   
    
    init?(dict:[String: Any])
    {
        print(dict)
        guard
            let _contact_no = dict["contact_no"] as? String,
            let _drug_licence = dict["drug_licence"] as? String,
            let _email = dict["email"] as? String,
            let _FirmAddress = dict["firm_address"] as? String,
            let _FirmName = dict["firm_name"] as? String,
            let _fssai_no = dict["fssai_no"] as? String,
            let _website_url = dict["website_url"] as? String,
            let _userid = dict["vendor_id"] as? String,
            let _user_type = dict["user_type"] as? String
            else {
                return nil
        }
        self.firm_name = _FirmName
        self.firm_address = _FirmAddress
        self.fssai_no = _fssai_no
        self.email = _email
        self.drug_licence = _drug_licence
        self.vendor_id = _userid
        self.website_url = _website_url
        self.contact_no = _contact_no
        self.user_type = _user_type
    }
}
struct getHomeProducts{
    var product_id :String
    var title :String
    var old_price : String
    var price :String
    var discount :String
    var code : String
    var brandName : String
    var min_quantity:String
    var product_status: String
}

struct getAllopathicProducts{
    var product_id :String
    var title :String
    var old_price : String
    var price :String
    var discount :String
    var code : String
    var brandName : String
    var min_quantity:String
    var product_status: String
}
struct getCartListing
{
    var product_id : String
    var title: String
    var price: String
    var quantity: String
    var total: String
}

 
