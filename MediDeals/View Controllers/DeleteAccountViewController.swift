//
//  DeleteAccountViewController.swift
//  MediDeals
//
//  Created by Claude on 2026-07-29.
//  Copyright © 2026 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class DeleteAccountViewController: UIViewController {

    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var deleteButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var warningLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Delete Account"
        self.navigationController?.navigationBar.isHidden = false
        Utilities.HideRightSideMenu()
        self.addLoadingIndicator()
        setupUI()
    }

    func setupUI() {
        warningLabel.text = "This action cannot be undone. All your data will be permanently deleted."
        warningLabel.textColor = UIColor.red
        deleteButton.setTitle("Delete My Account", for: .normal)
        deleteButton.setTitleColor(UIColor.white, for: .normal)
        deleteButton.backgroundColor = UIColor.red
        deleteButton.layer.cornerRadius = 5

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(UIColor.black, for: .normal)
        cancelButton.backgroundColor = UIColor.lightGray
        cancelButton.layer.cornerRadius = 5

        passwordTextField.placeholder = "Enter your password"
        passwordTextField.isSecureTextEntry = true
    }

    @IBAction func deleteAccountAction(_ sender: UIButton) {
        guard let password = passwordTextField.text, !password.isEmpty else {
            Utilities.ShowAlertView2(title: "Error", message: "Please enter your password", viewController: self)
            return
        }

        showConfirmationDialog(password: password)
    }

    @IBAction func cancelAction(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }

    func showConfirmationDialog(password: String) {
        let alertController = UIAlertController(
            title: "Confirm Account Deletion",
            message: "Are you sure you want to delete your account? This action cannot be undone.",
            preferredStyle: .alert
        )

        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alertController.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            self.performAccountDeletion(password: password)
        }))

        self.present(alertController, animated: true)
    }

    func performAccountDeletion(password: String) {
        self.startAnim()

        let params: [String: Any] = [
            "user_id": UserDefaults.standard.value(forKey: "USER_ID") ?? "",
            "password": password
        ]

        WebServicesManager.sharedInstance.httpRequest(
            methodName: "/delete_account",
            params: params as NSDictionary
        ) { response, error in
            DispatchQueue.main.async {
                self.stopAnim()

                if let error = error {
                    Utilities.ShowAlertView2(title: "Error", message: error, viewController: self)
                    return
                }

                guard let response = response as? NSDictionary else {
                    Utilities.ShowAlertView2(title: "Error", message: "Invalid response", viewController: self)
                    return
                }

                if let success = response["success"] as? Bool, success {
                    self.handleAccountDeletionSuccess()
                } else if let message = response["message"] as? String {
                    Utilities.ShowAlertView2(title: "Error", message: message, viewController: self)
                } else {
                    Utilities.ShowAlertView2(title: "Error", message: "Could not delete account", viewController: self)
                }
            }
        }
    }

    func handleAccountDeletionSuccess() {
        UserDefaults.standard.removeObject(forKey: "USER_ID")
        UserDefaults.standard.removeObject(forKey: "USER_NAME")
        UserDefaults.standard.removeObject(forKey: "USER_EMAIL")
        UserDefaults.standard.synchronize()

        let alertController = UIAlertController(
            title: "Success",
            message: "Your account has been deleted successfully.",
            preferredStyle: .alert
        )

        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            let vc = self.storyboard?.instantiateViewController(withIdentifier: "Login_ViewController") as! Login_ViewController
            let navController = UINavigationController(rootViewController: vc)
            self.view.window?.rootViewController = navController
            self.view.window?.makeKeyAndVisible()
        }))

        self.present(alertController, animated: true)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}
