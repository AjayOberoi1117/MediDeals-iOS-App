//
//  AboutUSViewController.swift
//  MediDeals
//
//  Created by SIERRA on 12/31/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class AboutUSViewController: UIViewController,UIWebViewDelegate {
    var actionString = ""
    @IBOutlet weak var webView: UIWebView!
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideRightSideMenu()
//        Utilities.AttachSideMenuController()
        self.webView.delegate = self
        if actionString == "aboutUS"{
            self.title = "About US"
            let stringurl =  "http://medideals.co.in/cdg/about_us.php"
            let url = URL(string: stringurl)
            let theRequest = NSMutableURLRequest(url: url!, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 0.0)
            self.webView.loadRequest((theRequest as URLRequest))
        }else if actionString == "PrivacyPolicy"{
            self.title = "Privacy & Policy"
            let stringurl =  "http://medideals.co.in/cdg/terms.php"
            let url = URL(string: stringurl)
            let theRequest = NSMutableURLRequest(url: url!, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 0.0)
            self.webView.loadRequest((theRequest as URLRequest))
        }
        
        // Do any additional setup after loading the view.
    }
    func webViewDidStartLoad(_ webView: UIWebView) {
        showProgress()
    }
    func webViewDidFinishLoad(_ webView: UIWebView) {
        hideProgress()
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    @IBAction func menuAct(_ sender: UIBarButtonItem) {
        Utilities.LeftSideMenu()
    }

   

}
