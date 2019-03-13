//
//  OTPViewController.swift
//  MediDeals
//
//  Created by VLL on 2/18/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class OTPViewController: UIViewController,VPMOTPViewDelegate {
    @IBOutlet var otpView: VPMOTPView!
    @IBOutlet weak var titleLbl: UILabel!
    
    var phnNumber = ""
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.isNavigationBarHidden = true
        self.titleLbl.text = "Please type the verification code sent to" + phnNumber
        otpView.otpFieldsCount = 4
        otpView.otpFieldDefaultBorderColor = UIColor.gray
        otpView.otpFieldEnteredBorderColor = UIColor.white
        otpView.otpFieldErrorBorderColor = UIColor.red
        otpView.otpFieldBorderWidth = 2
        otpView.delegate = self
        otpView.shouldAllowIntermediateEditing = false
        otpView.otpFieldDisplayType = .square
        // Create the UI
        otpView.initializeUI()
        // Do any additional setup after loading the view.
    }
    
    func shouldBecomeFirstResponderForOTP(otpFieldIndex index: Int) -> Bool {
        return true
    }
    func enteredOTP(otpString: String) {
        print(otpString)
    }
    
    func hasEnteredAllOTP(hasEntered: Bool) -> Bool {
        return true
    }
    
    @IBAction func otpBtn(_ sender: DesignableButton) {
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "AccountTypeViewController") as! AccountTypeViewController
        self.navigationController?.pushViewController(vc, animated: false)
    }
    
    @IBAction func backBtn(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
}
