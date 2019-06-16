//
//  BankDetailsVC.swift
//  MediDeals
//
//  Created by Pankaj Rana on 08/06/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

protocol TheDelegate: class {
    func didScroll(to position: CGFloat)
}

@available(iOS 11.0, *)
class BankDetailsVC: UIViewController, TheDelegate {
    func didScroll(to position: CGFloat) {
        for cell in BankDetailTableView.visibleCells as! [BankDetailsTableCell] {
            (cell.detailCollectionView as UIScrollView).contentOffset.x = position
        }
    }
    
    var cell = BankDetailsTableCell()
    var Action = ""
    @IBOutlet weak var BankDetailTableView: UITableView!
    @IBOutlet weak var hiddenView: UIView!
    @IBOutlet weak var AddDetailsView: UIView!
    override func viewDidLoad() {
        super.viewDidLoad()
        Utilities.HideLeftSideMenu()
        Utilities.HideRightSideMenu()
        self.AddDetailsView.isHidden = true
        self.hiddenView.isHidden = true
        Action = "no"
        // Do any additional setup after loading the view.
         self.hiddenView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTappedOnView)))
       
    }
    @IBAction func AddDetailsBtn(_ sender: UIBarButtonItem) {
        if Action == "no"{
            self.AddDetailsView.isHidden = false
            self.hiddenView.isHidden = false
            Action = "yes"
        }else{
            self.AddDetailsView.isHidden = true
            self.hiddenView.isHidden = true
            Action = "no"
        }
    }
    @objc func didTappedOnView(){
        self.AddDetailsView.isHidden = true
        self.hiddenView.isHidden = true
    }
    
}
@available(iOS 11.0, *)
extension BankDetailsVC : UITableViewDelegate, UITableViewDataSource{
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int{
        return 3
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! BankDetailsTableCell
        cell.detailCollectionView.tag = indexPath.row
        //tableCell.detailCollectionView.isPagingEnabled = true
        cell.scrollDelegate = self
        return cell
    }
    
}
@available(iOS 11.0, *)
extension BankDetailsVC : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout
{
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return BankDetailsTitles.count
        
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath as IndexPath) as? BankTitleCell
        {
            if collectionView.tag == 0{
                cell.name.text = BankDetailsTitles[indexPath.row]
                cell.name.textColor = UIColor.white
                cell.designView.backgroundColor = THEME_COLOR1
            }
            return cell
        }
        return UICollectionViewCell()
    }
    
    
}

extension BankDetailsTableCell: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollDelegate?.didScroll(to: scrollView.contentOffset.x)
    }
}

class BankDetailsTableCell: UITableViewCell{
    @IBOutlet weak var detailCollectionView: UICollectionView!
    weak var scrollDelegate: TheDelegate?
    override func awakeFromNib() {
        super.awakeFromNib()
        (detailCollectionView as UIScrollView).delegate = self
        
    }
}
class BankTitleCell:UICollectionViewCell{
    @IBOutlet weak var name: UILabel!
    @IBOutlet weak var designView: DesignableView!
    
}
