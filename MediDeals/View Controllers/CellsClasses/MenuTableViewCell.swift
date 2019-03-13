//
//  MenuTableViewCell.swift
//  MediDeals
//
//  Created by SIERRA on 1/31/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

class MenuTableViewCell: UITableViewCell {
    @IBOutlet weak var codelbl: UILabel!
    @IBOutlet var originalPrice: UILabel!
    @IBOutlet var brandName: UILabel!
    @IBOutlet weak var titleName: UILabel!
    @IBOutlet var discountPercent: UILabel!
    @IBOutlet weak var quantity: UILabel!
    
    @IBOutlet weak var addtoCart: DesignableButton!
    @IBOutlet weak var disPriceLbl: UILabel!
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
