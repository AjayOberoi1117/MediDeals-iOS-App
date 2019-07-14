
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
import UserNotifications
@available(iOS 11.0, *)
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate,NVActivityIndicatorViewable,UNUserNotificationCenterDelegate {
    var window: UIWindow?
    var centerContainer =  MMDrawerController()
    var firstName : String!
    var lastName : String!
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
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
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.foregroundColor:UIColor.white]
    
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
        UserDefaults.standard.set("6DF94241852968AD49898532F789D425730989850342818B60EE212", forKey: "DEVICETOKEN");
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
    
    
    
    
    
    
    

}

