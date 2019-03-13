
//
//  AppDelegate.swift
//  MediDeals
//
//  Created by SIERRA on 12/27/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import UIKit
import IQKeyboardManagerSwift
import MMDrawerController
import NVActivityIndicatorView
import FBSDKLoginKit
import FBSDKCoreKit
import FacebookLogin
import GoogleSignIn
import UserNotifications
@available(iOS 11.0, *)
@UIApplicationMain
class AppDelegate: UIResponder,GIDSignInDelegate, UIApplicationDelegate,NVActivityIndicatorViewable,UNUserNotificationCenterDelegate {
    var window: UIWindow?
    var centerContainer =  MMDrawerController()
    var gmailuserdictionary = [String : Any]()
    var firstName : String!
    var lastName : String!
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        // Override point for customization after application launch.
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options:[.badge, .alert, .sound]){(granted, error) in
            // Enable or disable features based on authorization.
        }
        application.registerForRemoteNotifications()
        
        //MARK: To check whether the notification is on or not
        UNUserNotificationCenter.current().getNotificationSettings(){(settings) in
            switch settings.soundSetting{
            case .enabled:
                print("enabled sound setting")
            case .disabled:
            print("setting has been disabled")
            case .notSupported:
                print("something vital went wrong here")
            }
        }
        
        IQKeyboardManager.shared.enable = true
        iniSideMenu()
        UIApplication.shared.statusBarStyle = UIStatusBarStyle.lightContent //For Status bar to be white in color
        UINavigationBar.appearance().barTintColor = THEME_COLOR
        UINavigationBar.appearance().tintColor = UIColor.white
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedStringKey.foregroundColor:UIColor.white]
        //MARK: use for facebook integration
        FBSDKApplicationDelegate.sharedInstance().application(application, didFinishLaunchingWithOptions: launchOptions)
        //MARK: Initialize google sign-in
        GIDSignIn.sharedInstance().clientID = "89202861452-d7ch3vvfvbfpaagpr5orr41bm6orlt9a.apps.googleusercontent.com"
        GIDSignIn.sharedInstance().delegate = self
        sleep(2)
        return true
    }
    
    
    func iniSideMenu(){
        let mainStoryBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
         // Get Reference to Center, Left Right View Controllers
        
        let centerViewController = mainStoryBoard.instantiateViewController(withIdentifier: "FirstViewController") as! FirstViewController
        
        let leftSideViewController = mainStoryBoard.instantiateViewController(withIdentifier: "SideMenuController") as! SideMenuController
        
        let rightSideViewController = mainStoryBoard.instantiateViewController(withIdentifier: "FilterViewController") as! FilterViewController
        let leftSideNav = UINavigationController(rootViewController: leftSideViewController)
        
        let centreNav = UINavigationController(rootViewController: centerViewController)
        
        let rightSideNav = UINavigationController(rootViewController: rightSideViewController)
        // Build the MMDrawerController
        
        centerContainer = MMDrawerController(center: centreNav, leftDrawerViewController: leftSideNav, rightDrawerViewController: rightSideNav)

        
        centerContainer.openDrawerGestureModeMask = MMOpenDrawerGestureMode.panningCenterView
        centerContainer.closeDrawerGestureModeMask = MMCloseDrawerGestureMode.panningCenterView
        window!.rootViewController = centerContainer
        window!.makeKeyAndVisible()
    }
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        let reachability = PMDReachabilityWrapper.sharedInstance()
        reachability?.monitorReachability()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        let reachability = PMDReachabilityWrapper.sharedInstance()
        reachability?.monitorReachability()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    //MARK: Delegate used to handle notification
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    {
        var token = ""
        for i in 0...deviceToken.count-1 {
            token = token + String(format: "%02.2hhx", arguments: [deviceToken[i]])
        }
        print("DEVICE TOKEN = \(deviceToken)")
        let deviceTokenString = deviceToken.reduce("", {$0 + String(format: "%02X", $1)})
        print(deviceTokenString)
        UserDefaults.standard.set(token, forKey: "DEVICETOKEN");
        UserDefaults.standard.synchronize();
        // UpdateLocation.upadteDeviceToke(token: token)
        // Define identifier
        let notificationName = Notification.Name("DEVICETOKEN_NOTI")
        // Post notification
        NotificationCenter.default.post(name: notificationName, object: nil)
    }
    //MARK: Delegate used for failure case
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set("55FEEFC57C0F70B6ACE95910854C5AC4B47806967211F58B55887CFA4E4B6A09", forKey: "DEVICETOKEN");
        UserDefaults.standard.synchronize();
        
        // Define identifier
        let notificationName = Notification.Name("DEVICETOKEN_NOTI")
        // Post notification
        NotificationCenter.default.post(name: notificationName, object: nil)
        print("i am not available in simulator \(error)")
        
    }
    // This method will be called when app received push notifications in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Swift.Void)
    {
        completionHandler([.alert,.sound,.badge])
    }
    
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void){
        
        print("User Info = ",response.notification.request.content.userInfo)
        //        window?.rootViewController?.childViewControllers.last?.navigationController?.viewControllers.last?.dismiss(animated: false, completion: nil)
        
        let story = UIStoryboard.init(name: "Main" , bundle: nil)
        let noti_dict = response.notification.request.content.userInfo as NSDictionary
        print(noti_dict)
        if noti_dict.value(forKeyPath: "payload.noti_type") as! String == "apply_job"{
//            let centerViewController = story.instantiateViewController(withIdentifier: "JobBoardViewController") as! JobBoardViewController
//            let centnav = UINavigationController(rootViewController:centerViewController)
//            centerContainer.centerViewController = centnav
//
//            let vc = story.instantiateViewController(withIdentifier: "JobBoardViewController") as! JobBoardViewController
//            centerViewController.navigationController?.pushViewController(vc, animated: false)
        }
        
        
    }
    
    
    
    
    
    
    func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        let handled: Bool = FBSDKApplicationDelegate.sharedInstance().application(application, open: url, sourceApplication: sourceApplication, annotation: annotation)
        // Add any custom logic here.
        return handled
    }
    // Swift
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        
        if(url.scheme!.isEqual("fb1973729969587292"))
        {
            return FBSDKApplicationDelegate.sharedInstance().application(app, open: url, sourceApplication: options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String!, annotation: options[UIApplicationOpenURLOptionsKey.annotation])
        }
        else if(url.scheme!.isEqual("com.googleusercontent.apps.89202861452-d7ch3vvfvbfpaagpr5orr41bm6orlt9a"))
        {
            return GIDSignIn.sharedInstance().handle(url as URL!,
                                                     sourceApplication: options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String!,
                                                     annotation: options[UIApplicationOpenURLOptionsKey.annotation])
        }
        else{
            return true
        }
    }
    func application(application: UIApplication,
                     openURL url: NSURL, sourceApplication: String?, annotation: AnyObject?) -> Bool {
        let options: [String: AnyObject] = [UIApplicationOpenURLOptionsKey.sourceApplication.rawValue: sourceApplication as AnyObject,
                                            UIApplicationOpenURLOptionsKey.annotation.rawValue: annotation!]
        print(options)
        return GIDSignIn.sharedInstance().handle(url as URL!,
                                                 sourceApplication: sourceApplication,
                                                 annotation: annotation)
    }
    
    func sign(_ signIn: GIDSignIn!, didDisconnectWith user: GIDGoogleUser!, withError error: Error!)
    {
        
    }
    func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser!, withError error: Error!) {
        if (error == nil){
            // Perform any operations on signed in user here.
            let userId: String = user.userID                  // For client-side use only!
            let idToken: String = user.authentication.idToken // Safe to send to the server
            let fullName: String = user.profile.name
            let givenName: String = user.profile.givenName
            let email: String = user.profile.email
            let picURL = user.profile.imageURL(withDimension: 120)
            gmailuserdictionary  = ["id" : userId, "Tokenid": idToken, "username" : fullName, "name" : givenName, "useremail" : email, "image" : picURL as Any]
            print(userId ,idToken ,fullName ,givenName ,email ,picURL as Any )
//            SingletonClass.sharedInstance.gmailuser_login = gmailuserdictionary as NSDictionary
            // ...
            let fullName1 : String = fullName
            let fullNameArr : [String] = fullName1.components(separatedBy: " ")
            // And then to ac cess the individual words:
            firstName = fullNameArr[0]
            lastName  = fullNameArr[1]
            print(firstName,lastName)
//            self.socialgmaillogin()
        }else
        {
            print("\(error.localizedDescription)")
        }
    }
    
    
//    func socialgmaillogin() {
//
//        let params = ["id": SingletonClass.sharedInstance.gmailuser_login.value(forKey: "id"),
//                      "login_type": "G",
//                      "email": SingletonClass.sharedInstance.gmailuser_login.value(forKey: "useremail"),
//                      "first_name": firstName,
//                      "last_name": lastName,
//                      "user_image": SingletonClass.sharedInstance.gmailuser_login.value(forKey: "image")]
//
//        WebService.webService.social_loginApi(params: params as NSDictionary){ _ in
//
//            // Define identifier
//            let notificationName = Notification.Name("GMAIL_NOTI")
//            // Post notification
//
//            NotificationCenter.default.post(name: notificationName, object: nil)
//            //           NotificationCenter.default.post(name: Notification.Name("GMAIL_NOTI"), object: nil)
//        }
//    }

}

