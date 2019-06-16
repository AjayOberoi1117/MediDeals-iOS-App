//
//  Extension.swift
//  loginWithApi
//
//  Created by SIERRA on 6/6/18.
//  Copyright © 2018 SIERRA. All rights reserved.
//

import Foundation
import UIKit
import NVActivityIndicatorView

fileprivate var activityIndicator : CustomActivityIndicatorView = {
    let image : UIImage = UIImage(named: "loader")!
    return CustomActivityIndicatorView(image: image)
}()
extension UIViewController: NVActivityIndicatorViewable
{ // show progress hud
    func showProgress() {
        // loader starts
        let size = CGSize(width: 50, height:50)
        self.startAnimating(size, message:"Loading", messageFont: UIFont.systemFont(ofSize: 18.0), type: NVActivityIndicatorType.ballScaleRippleMultiple, color: UIColor.white, padding: 1, displayTimeThreshold: nil, minimumDisplayTime: nil)
    }
// hide progress hud
    func hideProgress() {
        // stop loader
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1.0) {
            self.stopAnimating() }
    }
    func alert(title:String?,message:String?)
    {
        let alertView = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertView.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
        present(alertView, animated: true, completion: nil)
    }
    
    //MARK: Push Segue ...
    func performPushSeguefromController(identifier:String){
        let vc = storyboard?.instantiateViewController(withIdentifier: identifier)
        self.navigationController?.pushViewController(vc!, animated: true)
    }
    
    
    
}
extension UIView{
    // Shadow OUTPUT 1
    func dropShadow(scale: Bool = true) {
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowOffset = CGSize(width: -1, height: 1)
        layer.shadowRadius = 0.5
        
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
        layer.shouldRasterize = true
        layer.rasterizationScale = scale ? UIScreen.main.scale : 1
    }
    
 func startAnimation(){
        
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 1.0, delay: 0.0, options: [ .curveEaseInOut], animations: {
            
            self.alpha = 0
        }, completion: { _ in
            UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 1.0, delay: 0.0, options: [.curveEaseInOut], animations: {
                self.alpha = 1
            }, completion: { _ in
                
                self.startAnimation()
            })
        })
        
    }
     
}
extension UIViewController{
    func addLoadingIndicator () {
        self.view.addSubview(activityIndicator)
        activityIndicator.center = self.view.center
    }
    func startAnim() {
        //        backView.isHidden = false
        UIApplication.shared.beginIgnoringInteractionEvents()
        activityIndicator.startAnimating()
    }
    
    func stopAnim() {
        //        backView.isHidden = true
        activityIndicator.stopAnimating()
        UIApplication.shared.endIgnoringInteractionEvents()
    }
    
    func rotateImageAnimation(){
        let imageName = "Heart-hand-shake"
        let image = UIImage(named: imageName)
        let imageView = UIImageView(image: image!)
        imageView.frame = CGRect(x: 100, y: 150, width: 100, height: 100)
        self.view.addSubview(imageView)
        rotateView(targetView: imageView, duration: 0.5)
//        UIView.animate(withDuration: 0.5, delay: 0.45, options: UIViewAnimationOptions.curveEaseIn, animations: { () -> Void in
//            imageView.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi * 2.0))
//        }, completion: nil)
    }
    
    private func rotateView(targetView: UIView, duration: Double = 1.0) {
        UIView.animate(withDuration: duration, delay: 0.5, options: .curveEaseInOut, animations: {
            targetView.transform = targetView.transform.rotated(by: CGFloat(Double.pi))
        }) { finished in
            self.rotateView(targetView: targetView, duration: duration)
        }
    }
}
