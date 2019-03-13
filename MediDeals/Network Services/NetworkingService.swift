//
//  NetworkingService.swift
//  MVC-S
//
//  Created by Kyle Lee on 8/20/17.
//  Copyright © 2017 Kyle Lee. All rights reserved.
//

import Foundation
import Alamofire
class NetworkingService {
    
    private init() {}
    static let shared = NetworkingService()
   
    func getData(PostName: String,parameters: [String:String], completion: @escaping (Any)->Void) {
        let url = URL(string:baseUrl+PostName)
        let headers = ["content-type": "application/json"]
        Alamofire.request(url!, method:.post, parameters: parameters, encoding: JSONEncoding.default, headers: nil).responseJSON { response in
            switch(response.result) {
            case .success(_):
                if let data = response.result.value
                {
                    print(response.result.value as Any)
                    print(data)
                    DispatchQueue.main.async {
                    completion(data)}
                }
                break
            case .failure(_):
                print(response.result.error!)

                break
            }
        }
    }
    func getData4(PostName: String,parameters: [String:String], completion: @escaping (Any)->Void) {
        
        let url = URL(string:baseUrl+PostName)
        let headers = ["auth": "N6sa7EssImjHDBi2Q"]
        Alamofire.request(url!, method:.post, parameters: parameters, encoding: JSONEncoding.default, headers: headers).responseString { response in
            switch(response.result) {
                
            case .success(_):
                if let data = response.result.value
                {
                    print(response.result.value as Any)
                    print(data)
                    DispatchQueue.main.async {
                        completion(data)}
                }
                break
            case .failure(_):
                print(response.result.error!)
                
                break
            }
        }
    }
    
    func  getData2(PostName: String,parameters: [String:String], completion: @escaping (Any)->Void) {
        let url = URL(string:baseUrl+PostName)
        let headers = [ "content-type": "application/json", "token" : UserDefaults.standard.value(forKey: "TOKEN") as! String ]
        Alamofire.request(url!, method:.post, parameters: parameters, encoding: JSONEncoding.default, headers: headers).responseJSON { response in
            switch(response.result) {
                
            case .success(_):
                if let data = response.result.value
                {
                    print(response.result.value as Any)
                    print(data)
                    DispatchQueue.main.async {
                        completion(data)}
                }
                break
            case .failure(_):
                if let data = response.result.error
                {
                    print(response.result.value as Any)
                    print(data)
                }
                break
            }
        }
    }
    func  getData5(PostName: String, completion: @escaping (Any)->Void) {
        let url = URL(string:baseUrl+PostName)
//        let headers = [ "content-type": "application/json", "token" : UserDefaults.standard.value(forKey: "TOKEN") as! String ]
        Alamofire.request(url!, method:.post, parameters: nil, encoding: JSONEncoding.default, headers: nil).responseJSON { response in
            switch(response.result) {
                
            case .success(_):
                if let data = response.result.value
                {
                    print(response.result.value as Any)
                    print(data)
                    DispatchQueue.main.async {
                        completion(data)}
                }
                break
            case .failure(_):
                if let data = response.result.error
                {
                    print(response.result.value as Any)
                    print(data)
                }
                break
            }
        }
        
    }
    
    func getData3(PostName: String,parameters: [String:String], completion: @escaping (Any)->Void) {
        let url = URL(string:baseUrl+PostName)
        Alamofire.request(url!, method:.post, parameters: parameters, encoding: JSONEncoding.default, headers: nil).responseJSON { response in
            switch(response.result) {
                
            case .success(_):
                if let data = response.result.value
                {
                    print(response.result.value as Any)
                    print(data)
                    DispatchQueue.main.async {
                        completion(data)}
                }
                break
            case .failure(_):
                if let data = response.result.error
                {
                    print(response.result.value as Any)
                    print(data)
                }
                break
            }
        }
    }
}

extension UIViewController: URLSessionDataDelegate,URLSessionTaskDelegate,URLSessionDelegate{
    //MARK:=================================  UPLOAD IMAGE ==========================================
    func uploadImage(urlString:String,params:[String:String]?,imageKeyValue:String?,image:UIImage?,success:@escaping ( _ response: NSDictionary)-> Void, failure:@escaping ( _ error: Error) -> Void){
        
        let boundary: String = "------VohpleBoundary4QuqLuM1cE5lMwCy"
        let contentType: String = "multipart/form-data; boundary=\(boundary)"
        let headers :[String:String] =
            ["content-type": "application/json", "token" : UserDefaults.standard.value(forKey: "TOKEN") as! String]
        var request = URLRequest(url: URL(string: urlString)!)
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 60
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let body = NSMutableData()
        if let parameters = params {
            for (key, value) in parameters {
                body.append("--\(boundary)\r\n".data(using: String.Encoding.utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: String.Encoding.utf8)!)
                body.append("\(value)\r\n".data(using: String.Encoding.utf8)!)
            }
        }
        //which field you have to sent image on server
        let fileName: String = imageKeyValue!
        if image != nil {
            body.append("--\(boundary)\r\n".data(using: String.Encoding.utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(fileName)\"; filename=\"image.png\"\r\n".data(using: String.Encoding.utf8)!)
            body.append("Content-Type:image/png\r\n\r\n".data(using: String.Encoding.utf8)!)
            body.append(UIImageJPEGRepresentation(image!, 0.2)!)
            body.append("\r\n".data(using: String.Encoding.utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: String.Encoding.utf8)!)
        request.httpBody = body as Data
        //  let session = URLSession.shared
        let session = URLSession(configuration:.default, delegate: (self as URLSessionDelegate), delegateQueue: .main)
        // var session = NSURLSession(configuration: configuration, delegate: self, delegateQueue: NSOperationQueue.mainQueue())
        let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
            
            //   print(data as Any)
            DispatchQueue.main.async {
                // self.hideProgress()
                
                if(error != nil){
                    //  print(String(data: data!, encoding: .utf8) ?? "No response from server")
                    
                    failure(error!)
                    
                }
                if let responseData = data{
                    do {
                        let json = try JSONSerialization.jsonObject(with: responseData, options: [])
                        //      print(json)
                        success(json as! NSDictionary)
                        
                    }catch let err{
                        //    print(err)
                        
                        failure(err)
                        
                    }
                }
                
            }
            
        }
        task.resume()
    }

    //MARK:================================= UPLOAD DOCUMENT ==========================================
    func uploadDocuments(urlString:String,params:[String:String]?,documentUrl:URL?,success:@escaping ( _ response: NSDictionary)-> Void, failure:@escaping ( _ error: Error) -> Void){
        let boundary: String = "------VohpleBoundary4QuqLuM1cE5lMwCy"
        let contentType: String = "multipart/form-data; boundary=\(boundary)"
        let headers :[String:String] =
            [
                 "token" : UserDefaults.standard.value(forKey: "TOKEN") as! String
                ]
        var request = URLRequest(url: URL(string: urlString)!)
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 60
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let body = NSMutableData()
        if let parameters = params {
            for (key, value) in parameters {
                body.append("--\(boundary)\r\n".data(using: String.Encoding.utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: String.Encoding.utf8)!)
                body.append("\(value)\r\n".data(using: String.Encoding.utf8)!)
            }
        }
        //which field you have to sent image on server
        let fileName: String = "documents"
        
        
        if documentUrl != nil {
            body.append("--\(boundary)\r\n".data(using: String.Encoding.utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(fileName)\"; filename=\"application/pdf\"\r\n".data(using: String.Encoding.utf8)!)
            body.append("Content-Type:application/pdf\r\n\r\n".data(using: String.Encoding.utf8)!)
            body.append(NSData(contentsOf: documentUrl!)! as Data)
            body.append("\r\n".data(using: String.Encoding.utf8)!)
        }
        
        
        body.append("--\(boundary)--\r\n".data(using: String.Encoding.utf8)!)
        request.httpBody = body as Data
        let session = URLSession.shared
        let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
            
            DispatchQueue.main.async {
                self.hideProgress()
                
                if(error != nil){
                    // print(String(data: data!, encoding: .utf8) ?? "No response from server")
                    
                    failure(error!)
                    
                }
                
                
                if let responseData = data{
                    do {
                        let json = try JSONSerialization.jsonObject(with: responseData, options: [])
                        print(json)
                        success(json as! NSDictionary)
                        
                    }catch let err{
                        print(err)
                        
                        failure(err)
                        
                    }
                }
                
            }
            
        }
        task.resume()
    }
   
}





