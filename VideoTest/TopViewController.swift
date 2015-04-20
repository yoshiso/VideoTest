//
//  TopViewController.swift
//  VideoTest
//
//  Created by ShoYoshida on 2015/04/20.
//  Copyright (c) 2015年 ShoYoshida. All rights reserved.
//

import UIKit

class TopViewController: UIViewController {
    
    var cachePath: NSURL {
        get{
            return (NSFileManager.defaultManager().URLsForDirectory(.CachesDirectory, inDomains: .UserDomainMask)[0]) as NSURL
        }
    }
    
    @IBAction func Download(sender: UIButton) {
        dl()
    }
    
    @IBAction func Delete(sender: AnyObject) {
        del()
    }
    
    func dl(){
        download(.GET, "\(Const().URL)/movies/stream.mp4", { (temporaryURL, response) -> (NSURL) in
            println("tempurl")
            println(self.cachePath)

            let newPath = self.cachePath.URLByAppendingPathComponent("stream.mp4")
            return newPath
        }).progress { (reads, totalreads, expectedtotalreads) -> Void in
            let prog = Float(totalreads) / Float(expectedtotalreads)
            println("Progress: \(prog)")
        }.response { (request, response, _, error) in
            var path = (NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true)[0] as String).stringByAppendingPathComponent("stream.mp4")
            let status = NSFileManager.defaultManager().fileExistsAtPath(path)
            println("Exist Cache File?: \(status)")
        }
    }
    
    
    func del(){
        let fm = NSFileManager.defaultManager()
        var path = (NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true)[0] as String).stringByAppendingPathComponent("stream.mp4")
        if fm.fileExistsAtPath(path) {
            var err: NSError? = nil
            fm.removeItemAtPath(path, error: &err)
            if err == nil{
                println("Del Success")
            }else{
                println("Del Failed")
            }
            
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        var path = (NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true)[0] as String).stringByAppendingPathComponent("stream.mp4")
        let status = NSFileManager.defaultManager().fileExistsAtPath(path)
        println("Exist Cache File?: \(status)")
        
        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
}
