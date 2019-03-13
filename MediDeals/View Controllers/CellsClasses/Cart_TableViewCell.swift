//
//  Cart_TableViewCell.swift
//  MediDeals
//
//  Created by SIERRA on 1/2/19.
//  Copyright © 2019 SIERRA. All rights reserved.
//

import UIKit

class Cart_TableViewCell: UITableViewCell {
    @IBOutlet var deleteBtn: UIButton!
    @IBOutlet var quantity: UILabel!
    @IBOutlet var price: UILabel!
    @IBOutlet var productName: UILabel!
    @IBOutlet var btnPlus: UIButton!
    @IBOutlet var minusBtn: UIButton!
    @IBOutlet var lblValue: UITextField!
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
