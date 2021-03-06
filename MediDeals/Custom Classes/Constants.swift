//
//  Constants.swift
//  OSODCompany
//
//  Created by SIERRA on 7/16/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import Foundation
import UIKit
let baseUrl = "http://medideals.co.in/cdg/medideals/Api"
//"http://medideals.co.in/cdg/medideals/Api/"
//Medideals © 2019 All rights reserved.
let THEME_COLOR = UIColor(red: 0/255.0, green: 182/255.0, blue: 241/255.0, alpha: 0.0)
let THEME_COLOR1 = UIColor(red: 72/255.0, green: 181/255.0, blue: 237/255.0, alpha: 1.0)
let IMAGEBORDER_COLOR = UIColor(red: 0/255.0, green: 87/255.0, blue: 182/255.0, alpha: 1.0)
let PROFILEIMAGEBORDER_COLOR = UIColor(red: 182/255.0, green: 241/255.0, blue: 244/255.0, alpha: 1.0)
let SELECTION_COLOR = UIColor(red: 13/255.0, green: 206/255.0, blue: 220/255.0, alpha: 1.0)
let BUTTONSELECTION_COLOR = UIColor(red: 39/255.0, green: 170/255.0, blue: 75/255.0, alpha: 1.0)
let BUTTON_COLOR = UIColor(red: 72/255.0, green: 193/255.0, blue: 224/255.0, alpha: 1.0)
let FIRST_COLOR = UIColor(red: 29/255.0, green: 118/255.0, blue: 188/255.0, alpha: 1.0)
let SECOND_COLOR = UIColor(red: 41/255.0, green: 191/255.0, blue: 83/255.0, alpha: 1.0)
let THIRD_COLOR = UIColor(red: 249/255.0, green: 173/255.0, blue: 45/255.0, alpha: 1.0)
let FOURTH_COLOR = UIColor(red: 232/255.0, green: 68/255.0, blue: 65/255.0, alpha: 1.0)

let colorArraySeller = [FIRST_COLOR,SECOND_COLOR,THIRD_COLOR,FOURTH_COLOR,FIRST_COLOR,SECOND_COLOR]

let colorArrayBuyer = [FIRST_COLOR,SECOND_COLOR,THIRD_COLOR]

let colorArray10 = [FIRST_COLOR,SECOND_COLOR,THIRD_COLOR,FOURTH_COLOR,FIRST_COLOR,SECOND_COLOR,THIRD_COLOR,FOURTH_COLOR,FIRST_COLOR,SECOND_COLOR]

let colorArray8 = [FIRST_COLOR,SECOND_COLOR,THIRD_COLOR,FOURTH_COLOR,FIRST_COLOR,SECOND_COLOR,THIRD_COLOR,FOURTH_COLOR]

let SellerTitleName = ["Wholeseller Zone","Add Product","Show all Products","Subscription","Order Received","Bank Details"]

let BuyerTitleName = ["Order Placed","Enquiry Form","Show Responses"]

let SellerTitleImages = [UIImage(named: "seller")!,UIImage(named: "add")!,UIImage(named: "list")!,UIImage(named: "package")!,UIImage(named: "shopping-bag")!,UIImage(named: "bank-building")!]

let BuyerTitleImages = [UIImage(named: "package")!,UIImage(named: "file")!,UIImage(named: "list")!]

let DashBoardSellingName = ["Total Listed Products","Total Active Products","Total Inactive Products","Subscription End Date","Total Orders Received","Total Orders Dispatched","Total Orders Delivered","Total Orders Return","Total Revenue","Total Money in Escrow"]

let DashBoardSellingImages = [UIImage(named: "list")!,UIImage(named: "file")!,UIImage(named: "file")!,UIImage(named: "calendar")!,UIImage(named: "package")!,UIImage(named: "package")!,UIImage(named: "package")!,UIImage(named: "package")!,UIImage(named: "revenue")!,UIImage(named: "money")!]

let DashBoardBuyingName = ["Total Orders Placed","Total Orders Received","Total Orders Return","Total Products Received","Total Products Returned","Total Money Spend","Subscription End Date","Last Order"]

let DashBoardBuyingImages = [UIImage(named: "package")!,UIImage(named: "package")!,UIImage(named: "package")!,UIImage(named: "file")!,UIImage(named: "file")!,UIImage(named: "money")!,UIImage(named: "calendar")!,UIImage(named: "file")!]

let BankDetailsTitles = ["Id","Bank Name","Bank Account","Ifsc Code","Bank Address","Phone Number","Upi Number","Insert Date","Firm Name","Vendor Id"]

let orderStatusTitle = ["Confirmation Pending","Not Confirmed","Order Confirmed","Order Shipped","Order Delivered","Order Returned","Order Cancelled"]

let orderStatusTitleID = ["1","2","3","4","5","6","7"]

let PlacedOrderStatusTitle = ["Goods Received","Order Returned"]
public enum APIEndPoint
{
    public enum userCase {
        case userRegister
        case userLogin
        
        case newRegister
        case newLogin
        case verifyOtp
        case resendOtp
        case addInformation
        case logout
        
        case forgotPassword
        case SocialLogin
        case getProfile
        case editProfile
        case changePassword
        case update_device_id
        case update_lat_long
        case contact_us
        case get_brands
        case get_states
        case get_cities
        case get_product_detail
        case get_products
        case get_cat_products
        case add_Cart
        case get_cart
        case edit_cart
        case delete_cart
        case search
        case home
        case addProduct
        case showAllProduct
        case editProduct
        case deleteProduct
        case getBankDetail
        case addBankDetail
        case addEnquirie
        case getEnquirie
        case total_counts
        case orderReceived
        case addEditDocketNumber
        case changeOrderStatus
        case orderPlaced
        var caseValue: String{
            switch self{
            case .userRegister:               return "/register"
                
            case .newRegister:                return "/newRegister"
            case .newLogin:                   return "/newLogin"
            case .verifyOtp:                  return "/verifyOtp"
            case .resendOtp:                  return "/resendOtp"
            case .addInformation:             return "/addInformation"
            case .logout:                     return "/logout"
                
            case .userLogin:                  return "/login"
            case .forgotPassword:             return "/forgot_password"
            case .SocialLogin:                return "/SocialLogin"
            case .getProfile:                 return "/get_profile"
            case .editProfile:                return "/edit_profile"
            case .changePassword:             return "/change_password"
            case .update_device_id:           return "/update_device_id"
            case .update_lat_long:            return "/update_lat_long"
            case .contact_us:                 return"/contact_us"
            case .get_brands:                 return "/get_brands"
            case .get_states:                 return "/get_states"
            case .get_cities:                 return "/get_cities"
            case .get_product_detail:         return "/get_product_detail"
            case .get_products:               return "/get_products"
            case .get_cat_products:           return "/get_cat_products"
            case .add_Cart:                   return "/add_cart"
            case .get_cart:                   return "/get_cart"
            case .edit_cart:                  return "/edit_cart"
            case .delete_cart:                return "/delete_cart"
            case .home:                       return "/home"
            case .search:                     return "/search"
            case .addProduct:                 return "/addProduct"
            case .showAllProduct:             return "/showAllProduct"
            case .editProduct:                return "/editProduct"
            case .deleteProduct:              return "/deleteProduct"
            case .getBankDetail:              return "/getBankDetail"
            case .addBankDetail:              return "/addBankDetail"
            case .addEnquirie:                return "/addEnquirie"
            case .getEnquirie:                return "/getEnquirie"
            case .total_counts:               return "/total_counts"
            case .orderReceived:              return "/orderReceived"
            case .addEditDocketNumber:        return "/addEditDocketNumber"
            case .changeOrderStatus:          return "/changeOrderStatus"
            case .orderPlaced:                return "/orderPlaced"
            }
        }
    }
   
}

