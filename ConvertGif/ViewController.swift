//
//  ViewController.swift
//  ConvertGif
//
//  Created by kyongjin on 26/02/2019.
//  Copyright © 2019 claire. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    @IBAction func convertAction(_ sender: Any) {
        let converter = Converter()
        converter.convertGifFile()
    }
}

