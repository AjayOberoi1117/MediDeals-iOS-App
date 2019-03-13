//
//  SettingsViewController.swift
//  MediDeals
//
//  Created by SIERRA on 12/31/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class SettingsViewController: UIViewController {

    @IBAction func sideMenu(_ sender: UIBarButtonItem) {
        Utilities.LeftSideMenu()
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideRightSideMenu()
        // Do any additional setup after loading the view.
    }
    @IBAction func changePasswrdBtn(_ sender: UIButton) {
        let vc = storyboard?.instantiateViewController(withIdentifier: "ChangePasswordViewController") as! ChangePasswordViewController
        self.navigationController?.pushViewController(vc, animated: true)
    }
    @IBOutlet var changePwdBtn: UIButton!

    @IBAction func privacyPolicy(_ sender: UIButton){
        let vc = storyboard?.instantiateViewController(withIdentifier: "AboutUSViewController") as! AboutUSViewController
        vc.actionString = "PrivacyPolicy"
        self.navigationController?.pushViewController(vc, animated: true)
    }
    @IBAction func aboutUs(_ sender: UIButton){
        let vc = storyboard?.instantiateViewController(withIdentifier: "AboutUSViewController") as! AboutUSViewController
        vc.actionString = "aboutUS"
        self.navigationController?.pushViewController(vc, animated: true)
    }
    override func didReceiveMemoryWarning(){
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
