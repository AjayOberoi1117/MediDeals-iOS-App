//
//  SideMenuController.swift
//  OSODCompany
//
//  Created by SIERRA on 7/13/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit
import MMDrawerController
import SDWebImage
@available(iOS 11.0, *)
class SideMenuController: UIViewController, UITableViewDelegate , UITableViewDataSource {

    @IBOutlet weak var loginView: UIView!
    @IBOutlet var SideMenuTable: UITableView!
    @IBOutlet var profileImage: UIImageView!
    @IBOutlet var _lblName: UILabel!
    @IBOutlet var _lblEmail: UILabel!
  
    var side_menu = [String]()
    var cell = SideMenuTableCell()
    var newArry = NSMutableArray()
    override func viewDidLoad()
    {
        super.viewDidLoad()
        if UserDefaults.standard.value(forKey: "USER_ID") != nil{
        side_menu = ["Home","My Account","Allopathic", "Ayurvedic", "FMCG","PCD/3rd Party","Surgical Goods","Generics","Contact Us","Settings","Logout"]
        }else{
             side_menu = ["Home","My Account","Allopathic", "Ayurvedic", "FMCG","PCD/3rd Party","Surgical Goods","Generics","Contact Us","Settings"]
        }
        for _ in 0..<side_menu.count{
            newArry.add("0")
        }
        self.navigationController?.navigationBar.isHidden=true
        SideMenuTable.isScrollEnabled = false
        
        
        // Do any additional setup after loading the view.
    }
    override func viewWillAppear(_ animated: Bool) {
        if UserDefaults.standard.value(forKey: "PROFILE_NAME") != nil && UserDefaults.standard.value(forKey: "PROFILE_EMAIL")  != nil{
            self._lblName.text = (UserDefaults.standard.value(forKey: "PROFILE_NAME") as! String)
            self._lblEmail.text = (UserDefaults.standard.value(forKey: "PROFILE_EMAIL") as! String)
            self.loginView.isHidden = true
       }else{
            self.loginView.isHidden = false
        }
    }
    
    @IBAction func logInButton(_ sender: UIButton) {
        self.LogoutFunction()
    }
    //MARK: - TABLEVIEW METHODS
    override func didReceiveMemoryWarning()
    {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
   
    @IBAction func ProfileEditBtn(_ sender: UIButton) {
        let centerViewController = self.storyboard?.instantiateViewController(withIdentifier: "ProfileViewController") as! ProfileViewController
        let centnav = UINavigationController(rootViewController:centerViewController)
        let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
        // navigationController?.isNavigationBarHidden=true
        appDelegate.centerContainer.centerViewController = centnav
        appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        return side_menu.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        cell = SideMenuTable.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SideMenuTableCell
        cell.labelOutlet.text = side_menu[indexPath.row]
        if newArry[indexPath.row] as! String == "1"{
            cell.labelOutlet.textColor = SELECTION_COLOR
        }else{
            cell.labelOutlet.textColor = UIColor.lightGray
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        self.newArry = NSMutableArray()
        for _ in 0..<side_menu.count{
            newArry.add("0")
        }
        self.newArry.replaceObject(at: indexPath.row, with: "1")
        SideMenuTable.reloadData()
        if indexPath.row == 0
        {
            let centerViewController = storyboard?.instantiateViewController(withIdentifier: "Home_ViewController") as! Home_ViewController
            let centnav = UINavigationController(rootViewController:centerViewController)
            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.centerContainer.centerViewController = centnav
            appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)

        }
        if indexPath.row == 1
        {
            let centerViewController = storyboard?.instantiateViewController(withIdentifier: "MyAccountViewController") as! MyAccountViewController
            let centnav = UINavigationController(rootViewController:centerViewController)
            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.centerContainer.centerViewController = centnav
            appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)
            
        }
        if indexPath.row == 2
        {
            let centerViewController = storyboard?.instantiateViewController(withIdentifier: "MenuViewController") as! MenuViewController
            centerViewController.titleName = "Allopathic"
            centerViewController.catID = "1"
            let centnav = UINavigationController(rootViewController:centerViewController)
            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.centerContainer.centerViewController = centnav
            appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)

        }
        if indexPath.row == 3
        {
            let centerViewController = storyboard?.instantiateViewController(withIdentifier: "MenuViewController") as! MenuViewController
            centerViewController.titleName = "Ayurvedic"
            centerViewController.catID = "2"
            let centnav = UINavigationController(rootViewController:centerViewController)
            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.centerContainer.centerViewController = centnav
            appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)
            
        }
        if indexPath.row == 4
        {
            let centerViewController = storyboard?.instantiateViewController(withIdentifier: "MenuViewController") as! MenuViewController
            centerViewController.titleName = "FMCG"
            centerViewController.catID = "3"
            let centnav = UINavigationController(rootViewController:centerViewController)
            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.centerContainer.centerViewController = centnav
            appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)
            
        }
        if indexPath.row == 5
        {
            let centerViewController = storyboard?.instantiateViewController(withIdentifier: "MenuViewController") as! MenuViewController
            centerViewController.titleName = "PCD/3rd Party"
            centerViewController.catID = "3"
            let centnav = UINavigationController(rootViewController:centerViewController)
            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.centerContainer.centerViewController = centnav
            appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)
        }
      
        if indexPath.row == 6
        {
            let centerViewController = storyboard?.instantiateViewController(withIdentifier: "MenuViewController") as! MenuViewController
            centerViewController.titleName = "Surgical Goods"
            centerViewController.catID = "3"
            let centnav = UINavigationController(rootViewController:centerViewController)
            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.centerContainer.centerViewController = centnav
            appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)

        }
        if indexPath.row == 7
        {
            let centerViewController = storyboard?.instantiateViewController(withIdentifier: "MenuViewController") as! MenuViewController
            centerViewController.titleName = "Generics"
            centerViewController.catID = "3"
            let centnav = UINavigationController(rootViewController:centerViewController)
            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.centerContainer.centerViewController = centnav
            appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)
        }
        if indexPath.row == 8
        {
            let centerViewController = storyboard?.instantiateViewController(withIdentifier: "ContactUsViewController") as! ContactUsViewController
            let centnav = UINavigationController(rootViewController:centerViewController)
            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.centerContainer.centerViewController = centnav
            appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)
        }
         
        
        if indexPath.row == 9{
            let centerViewController = storyboard?.instantiateViewController(withIdentifier: "SettingsViewController") as! SettingsViewController
             let centnav = UINavigationController(rootViewController:centerViewController)
            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.centerContainer.centerViewController = centnav
            appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: true, completion: nil)
        }
        else if indexPath.row == 10{
            let refreshAlert = UIAlertController(title: "Alert", message: "Are you sure you want to logout?", preferredStyle: UIAlertControllerStyle.alert)

            refreshAlert.addAction(UIAlertAction(title: "Confirm", style: .default, handler: { (action: UIAlertAction!) in
                print("Handle Ok logic here")
                self.clearData()
            }))
            refreshAlert.addAction(UIAlertAction(title: "Cancel", style: .destructive, handler: { (action: UIAlertAction!) in
                print("Handle Cancel Logic here")
                refreshAlert .dismiss(animated: true, completion: nil)
            }))
            self.present(refreshAlert, animated: true, completion: nil)
        }

    }
  
    func LogoutFunction(){
        let centerViewController = self.storyboard?.instantiateViewController(withIdentifier: "Login2ViewController") as! Login2ViewController
        let centnav = UINavigationController(rootViewController:centerViewController)
        let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
        // navigationController?.isNavigationBarHidden=true
        appDelegate.centerContainer.centerViewController = centnav
        appDelegate.centerContainer.toggle(MMDrawerSide.left, animated: false, completion: nil)
        appDelegate.centerContainer.leftDrawerViewController = nil
    }
    
    func clearData(){
        
        logoutApi()
     }
    
    func logoutApi(){
        let params = ["vendor_id" : UserDefaults.standard.value(forKey: "USER_ID") as! String, "login_status": "2"]
        NetworkingService.shared.getData(PostName: APIEndPoint.userCase.logout.caseValue,parameters: params) { (response) in
            print(response)
            let dic = response as! NSDictionary
            print(dic)
            if (dic.value(forKey: "status") as? String == "0")
            {
                self.stopAnim()
                Utilities.ShowAlertView2(title: "Alert", message: dic.value(forKey: "message") as! String, viewController: self)
            } else {
                self.stopAnim()
                UserDefaults.standard.removeObject(forKey: "PROFILEIMAGE")
                UserDefaults.standard.removeObject(forKey: "PROFILE_EMAIL")
                UserDefaults.standard.removeObject(forKey: "PROFILE_NAME")
                UserDefaults.standard.removeObject(forKey: "USER_ID")
                UserDefaults.standard.synchronize()
                self.LogoutFunction()
            }
        }
    }
}
class SideMenuTableCell: UITableViewCell {
    @IBOutlet var labelOutlet: UILabel!
}
