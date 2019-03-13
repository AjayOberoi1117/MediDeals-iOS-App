//
//  WebServicesManager.swift
//  Topliners
//
//  Created by Vlad Minea on 12/07/2017.
//  Copyright © 2017 CodKom. All rights reserved.
//
import Foundation
import Alamofire
public enum APIEndPoint1
{
    public enum userCase1 {
        case forgotPassword
        var caseValue: String{
            switch self{
            case .forgotPassword: return "/forgot_password"
        
            }
        }
    }
}

struct WebServiceError: Error{
    var message: String?
}
public struct WebServicesManager {
    static let sharedInstance = WebServicesManager()
    private init(){}
    static var authorizationHeader: String?
    typealias SuccessClosure = (_ response: Any) -> Void
//    public typealias FailureClosure = (_ error: Error?, _ statusCode: Int?) -> Void
    typealias FailureClosure = (_ error: WebServiceError?, _ statusCode: Int?) -> Void
    
    
 func makeRequest(_ urlString: String, method: HTTPMethod, parameters: Parameters?, success: @escaping SuccessClosure, failure: @escaping FailureClosure) {
        
//        var headers: HTTPHeaders = ["Content-Type": "application/json"]
//
//        if let authorizationHeader = WebServicesManager.authorizationHeader
//        {
//            Mygrobal.header = authorizationHeader
//            headers["Authorization"] = authorizationHeader
//        }
        
        let url = baseUrl + urlString
        var parameterEncoding: ParameterEncoding = JSONEncoding.default
        
        if method == .post {
            parameterEncoding = URLEncoding.default
        }
       
      let request = Alamofire.request(url, method: method, parameters: parameters, encoding: parameterEncoding, headers: nil)
        
        request.validate(statusCode: 200..<600)
            .validate(contentType: ["application/json"])
            .responseJSON{ (response) -> Void in
                guard response.result.isSuccess else {
                    print("error on request \(response.result.error!)")
//                    failure(response.result.error, response.response?.statusCode)
                    return
                }
            
                guard let value = response.result.value else {
                    print("error on request bad result format")
//                    failure(response.result.error, response.response?.statusCode)
                    return
                }
                
                success(value)
                debugPrint(response)
                print("Response JSON: \(value)")
        }
        .responseString { (response) in
            print("STRING RESPONSE")
            debugPrint(response)
        }
    }
    
    
    fileprivate func makeRequest1(_ urlString: String, method: HTTPMethod, parameters: Parameters?, success: @escaping SuccessClosure, failure: @escaping FailureClosure){
        
//        var headers: HTTPHeaders = ["Content-Type": "application/json"]
//
//        if let authorizationHeader = WebServicesManager.authorizationHeader
//
//
//        {
//
//            Mygrobal.header = authorizationHeader
//
//            headers["Authorization"] = authorizationHeader
//        }
        
        let url = baseUrl + urlString
        var parameterEncoding: ParameterEncoding = JSONEncoding.default
        
        if method == .get || method == .delete {
            parameterEncoding = URLEncoding.default
        }
        
//        print(Mygrobal.header)
       
        let request = Alamofire.request(url, method: method, parameters: parameters, encoding: parameterEncoding, headers: nil)
        
        request.validate(statusCode: 200..<600)
            .validate(contentType: ["application/json"])
            .responseJSON{ (response) -> Void in
                guard response.result.isSuccess else {
                    print("error on request \(response.result.error!)")
                    //                    failure(response.result.error, response.response?.statusCode)
                    return
                }
                
                guard let value = response.result.value else {
                    print("error on request bad result format")
                    //                    failure(response.result.error, response.response?.statusCode)
                    return
                }
                
                success(value)
                debugPrint(response)
                print("Response JSON: \(value)")
            }
            .responseString { (response) in
                print("STRING RESPONSE")
                debugPrint(response)
        }
    }
    
    func httpRequest(methodName : String,params : NSDictionary, completion: @escaping (_ response:Any?,_ error:String?)->()) {
        print("Http Request params \(params)")
        
        print(baseUrl)
        
        Alamofire.request(baseUrl+methodName, method:.post, parameters: params as? Parameters, encoding: URLEncoding.default, headers: nil).responseJSON { response in
            switch(response.result) {
                
            // api is hit successfully
            case .success(_):
                
                // if error in data parsed from api response
                // check status
                guard let data : NSDictionary = response.result.value as! NSDictionary? else {
                    
                    // if error in getting data from response
                    print("Api Hit Successfully, Parsing Data Error")
                    completion(nil,"Api Hit Successfully, Parsing Data Error")
                    return
                }
                // api hit successfully and parsing is good
                print("Api Hit Successfully, Response \(data)")
                
                
                // check if status is 0 or 1
                
                guard let status =  Int((data.value(forKey: "status") as! String)), status == 1
                    else
                {
                    
                    //                     if status is 0
                    //                      print("Status \(status)")
                    //                     print("Message \(data.value(forKey: "message"))")
                    
                    
                    completion(nil,data.value(forKey: "message") as! String?)
                    //
                    //                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1.0) {
                    //                        self.stopAnimating() }
                    
                    return
                }
                // if status is 1, pass the dictionary back to caller
                completion(data,nil)
                
                break
                
            //  api hit failure
            case .failure(_):
                print("Api Hit Failure\(response.result.error!.localizedDescription)")
                // error is passed as string , response is kept nil
                
                completion(nil,"Api hit failure, please try again")
                
                break
                
            }
        }
        
    }
    //MARK: Image Uploading
    
  fileprivate  func httpRequestWithImage(methodName : String,image : UIImage,imageName : String? = nil,resolution : Float? = nil, params : NSDictionary, completion: @escaping (_ response:Any?,_ error:String?)->()) {
        
        
        var imageToUploadName = "image"
        if(imageName != nil) {
            imageToUploadName = imageName!
        }
        
        var imageResolution : Float = 0.2
        if(resolution != nil) {
            
            imageResolution = resolution!
            
        }
        
        Alamofire.upload(multipartFormData: {
            
            (multipartFormData) in
            
            multipartFormData.append(UIImageJPEGRepresentation(image, CGFloat(imageResolution))!, withName: imageToUploadName, fileName: "file.jpeg", mimeType: "image/jpeg")
            
            
            for (key, value) in params {
                multipartFormData.append((value as AnyObject).data(using: String.Encoding.utf8.rawValue)!, withName: key as! String)
            }
        },
                         to:baseUrl+methodName) {
                            
                            (result) in
                            
                            switch result {
                                
                            // api hit success
                            case .success(let upload, _, _):
                                
                                upload.uploadProgress(closure: { (progress) in
                                    //Print progress
                                    print("Progress \(progress.description)")
                                })
                                
                                upload.responseJSON { response in
                                    //print response.result
                                    guard let data : NSDictionary = response.result.value as! NSDictionary? else {
                                        
                                        // if error in getting data from response
                                        print("Api Hit Successfully, Parsing Data Error")
                                        completion(nil,nil)
                                        return
                                    }
                                    // api hit successfully and parsing is good
                                    print("Api Hit Successfully, Response \(data)")
                                    
                                    // check if status is 0 or 1
                                    
                                    guard let status =  Int((data.value(forKey: "status") as! String)), status == 1 else {
                                        
                                        // if status is 0
                                        //  print("Status \(status)")
                                        // print("Message \(data.value(forKey: "message"))")
                                        completion(nil,data.value(forKey: "message") as! String?)
                                        return
                                    }
                                    // if status is 1, pass the dictionary back to caller
                                    completion(data.value(forKey: "result"),nil)
                                }
                                
                            case .failure(_):
                                
                                completion(nil,"Api hit failure, please try again")
                                break
                                //print encodingError.description
                            }
        }
    }
    
    
    //MARK: THIS IS USED FOR NSURL SESSION METHODS>>>>
    func webservicesPostRequestNEW(baseString: String, parameters: String?,success:@escaping ( _ response: Any)-> Void, failure:@escaping ( _ error: Error) -> Void){
        
        let sessionConfiguration = URLSessionConfiguration.default
    
        let session = URLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: OperationQueue.main)
        
        let url = baseUrl + baseString
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.httpBody = parameters?.data(using: .utf8)
        
        let dataTask = session.dataTask(with: request) { (data: Data?, response: URLResponse?, error: Error?) in
            if error == nil{
                if let responseData = data{
                    do {
                       // let json = try JSONSerialization.jsonObject(with: responseData, options: []) as! [String: AnyObject]
                        let json = try JSONSerialization.jsonObject(with: responseData, options: [])
                        success(json)
                    }catch let err{
                        print(err)
                    
                    }
                }
            }else{
                failure(error!)
            }
        }
        dataTask.resume()
    }
    
    func webservicesPostRequest(baseString: String, parameters: [String:String],success:@escaping (_ response: NSDictionary)-> Void, failure:@escaping (_ error: Error) -> Void){
        
        let headers =
            [
                "auth": "N6sa7EssImjHDBi2Q",
                
            ]
        let sessionConfiguration = URLSessionConfiguration.default
        
        let session = URLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: OperationQueue.main)
        
        let jsonData = try? JSONSerialization.data(withJSONObject:parameters)
        
        let url = baseUrl + baseString
        
        //let url = baseString
        
        print(url)
        print(parameters)
        
        var request = URLRequest(url: URL(string: url)!)
        request.allHTTPHeaderFields = headers
        request.httpMethod = "POST"
        request.httpBody = jsonData
        
        let dataTask = session.dataTask(with: request) { (data: Data?, response: URLResponse?, error: Error?) in
            if error == nil{
                if let responseData = data{
                    do {
                        let json = try JSONSerialization.jsonObject(with: responseData, options: [])
                        success(json as! NSDictionary)
                    }catch let err{
                        print(err)
                        failure(err)
                        
                    }
                }
            }else{
                failure(error!)
            }
        }
        dataTask.resume()
    }
    
    func webServiceGetRequest(baseString: String, parameters: String?, success:@escaping (_ response: Any) ->Void, failure:@escaping (_ error: Error) -> Void){
        
        let sessionConfiguration = URLSessionConfiguration.default
        
        let session = URLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: OperationQueue.main)
        let url = URL(string: baseString)
        
        
        
        
        let dataTask = session.dataTask(with: url!, completionHandler: { (data: Data?, response: URLResponse?,error: Error?) in
            if error == nil{
                if let responseData = data{
                    do {
                        let json = try JSONSerialization.jsonObject(with: responseData, options: [])
                        success(json)
                    }catch let err{
                        
                        print(err)
                    }
                }
            }else{
                failure(error!)
            }
        })
        dataTask.resume()
    }
    
    
}
   
