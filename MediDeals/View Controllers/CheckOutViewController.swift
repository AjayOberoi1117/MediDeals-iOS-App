//
//  CheckOutViewController.swift
//  MediDeals
//
//  Created by SIERRA on 2/5/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

@available(iOS 11.0, *)
class CheckOutViewController: UIViewController  {
    
    @IBOutlet var bottomBtn: UIButton!
    @IBOutlet var paymentInstruTextView: UITextView!
    @IBOutlet var paymentMethodView: UIView!
    @IBOutlet var paymentImage: UIImageView!
    @IBOutlet var thirdView: UIView!
    @IBOutlet var checkImage: UIImageView!
    @IBOutlet var thirdLineView: UIView!
    @IBOutlet var shippingImage: UIImageView!
    @IBOutlet var secondView: UIView!
    @IBOutlet var secondLineView: UIView!
    @IBOutlet var firstView: DesignableView!
    @IBOutlet var firstlineView: UIView!
    override func viewDidLoad() {
        super.viewDidLoad()
        bottomBtn.setTitle("NEXT - PAYMENT INFO", for: .normal)
        self.firstView.isHidden = false
        self.secondView.isHidden = true
        self.thirdView.isHidden = true
        self.firstlineView.isHidden = false
        self.secondLineView.isHidden = true
        self.thirdLineView.isHidden = true
        Utilities.AttachSideMenuController()
        
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        paymentInstruTextView.setContentOffset(CGPoint.zero, animated: false)
    }
    @IBOutlet var backfromTextViewBtn: UIButton!
    @IBAction func backBtnFromTextView(_ sender: UIButton){
        self.paymentMethodView.isHidden = false
    }
    @IBAction func sideMenu(_ sender: UIBarButtonItem) {
        Utilities.LeftSideMenu()
    }
    @IBAction func bottomBtn(_ sender: UIButton){
        if  bottomBtn.titleLabel?.text == "NEXT - PAYMENT INFO"{
            if SingletonVariables.sharedInstace.checkShippingAddress == "yes"{
            bottomBtn.setTitle("NEXT - PROCEED TO PAYMENT", for: .normal)
            self.firstView.isHidden = true
            self.secondView.isHidden = false
            self.paymentMethodView.isHidden = false
            self.paymentInstruTextView.isHidden = true
            self.paymentInstruTextView.isEditable = false
            self.thirdView.isHidden = true
            paymentImage.image = #imageLiteral(resourceName: "credit-card (1)")
            shippingImage.image = #imageLiteral(resourceName: "home-address")
            checkImage.image = #imageLiteral(resourceName: "checked")
            self.firstlineView.isHidden = true
            self.secondLineView.isHidden = false
            self.thirdLineView.isHidden = true
            
                print(SingletonVariables.sharedInstace.ShippingAddress)
            }else{
                Utilities.ShowAlertView2(title: "Alert", message: "Please fill all inputs for shipping address", viewController: self)
            }
        }else if bottomBtn.titleLabel?.text == "NEXT - PROCEED TO PAYMENT"{
            bottomBtn.setTitle("NEXT - CONTINUE SHOPPING", for: .normal)
            self.firstView.isHidden = true
            self.secondView.isHidden = true
            self.thirdView.isHidden = false
            paymentImage.image = #imageLiteral(resourceName: "credit-card")
            shippingImage.image = #imageLiteral(resourceName: "home-address")
            checkImage.image = #imageLiteral(resourceName: "credit-card (1)")
            self.firstlineView.isHidden = true
            self.secondLineView.isHidden = true
            self.thirdLineView.isHidden = false
        }else if bottomBtn.titleLabel?.text == "NEXT - CONTINUE SHOPPING"{
            let vc = self.storyboard?.instantiateViewController(withIdentifier: "Home_ViewController") as! Home_ViewController
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    @IBAction func firstView(_ sender: UIButton){
        bottomBtn.setTitle("NEXT - PAYMENT INFO", for: .normal)
        self.firstView.isHidden = false
        self.secondView.isHidden = true
        self.thirdView.isHidden = true
        paymentImage.image = #imageLiteral(resourceName: "credit-card")
        shippingImage.image = #imageLiteral(resourceName: "home-address (1)")
        checkImage.image = #imageLiteral(resourceName: "checked")
        self.firstlineView.isHidden = false
        self.secondLineView.isHidden = true
        self.thirdLineView.isHidden = true
    }
    
    @IBAction func secondView(_ sender: UIButton) {
        bottomBtn.setTitle("NEXT - PROCEED TO PAYMENT", for: .normal)
        self.firstView.isHidden = true
        self.secondView.isHidden = false
        self.paymentMethodView.isHidden = false
        self.paymentInstruTextView.isHidden = true
     self.paymentInstruTextView.isEditable = false
        self.thirdView.isHidden = true
        paymentImage.image = #imageLiteral(resourceName: "credit-card (1)")
        shippingImage.image = #imageLiteral(resourceName: "home-address")
        checkImage.image = #imageLiteral(resourceName: "checked")
        self.firstlineView.isHidden = true
        self.secondLineView.isHidden = false
        self.thirdLineView.isHidden = true
    }
    
    @IBAction func thirdView(_ sender: UIButton){
        bottomBtn.setTitle("NEXT - CONTINUE SHOPPING", for: .normal)
        self.firstView.isHidden = true
        self.secondView.isHidden = true
        self.thirdView.isHidden = false
        paymentImage.image = #imageLiteral(resourceName: "credit-card")
        shippingImage.image = #imageLiteral(resourceName: "home-address")
        checkImage.image = #imageLiteral(resourceName: "checked (1)")
        self.firstlineView.isHidden = true
        self.secondLineView.isHidden = true
        self.thirdLineView.isHidden = false
    }
    @IBAction func bankTransferBtn(_ sender: UIButton){
        self.paymentMethodView.isHidden = true
        self.paymentInstruTextView.isHidden = false
    }
    
    @IBAction func paytmBtn(_ sender: UIButton) {
    }
    @IBAction func codBtn(_ sender: UIButton) {
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
