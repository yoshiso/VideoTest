//
//  VideoViewController.swift
//  VideoTest
//
//  Created by ShoYoshida on 2015/04/13.
//  Copyright (c) 2015年 ShoYoshida. All rights reserved.
//

import UIKit
import AVFoundation

let ViewControllerVideoPath = "http://192.168.59.103/movies/stream.m3u8"


// KVO contexts

private var PlayerObserverContext = 0
private var PlayerItemObserverContext = 0
private var PlayerLayerObserverContext = 0

// KVO playerLayer
private let PlayerReadyForDisplay = "readyForDisplay"

// KVO playerItem
private let PlayerStatusKey      = "status"
private let PlayerEmptyBufferKey = "playbackBufferEmpty"
private let PlayerKeepUpKey      = "playbackLikelyToKeepUp"

// KVO player
private let PlayerTracksKey   = "tracks"
private let PlayerPlayableKey = "playable"
private let PlayerDurationKey = "duration"
private let PlayerRateKey     = "rate"


public enum YSSPlayerState: Int, Printable {
    case Stopped = 0
    case Playing
    case Paused
    case Failed
    
    public var description: String {
        get {
            switch self {
            case .Stopped:
                return "Stopped"
            case .Playing:
                return "Playing"
            case .Failed:
                return "Failed"
            case Paused:
                return "Paused"
            }
        }
    }
}

public enum YSSBufferingState: Int, Printable {
    case Unknown = 0
    case Ready
    case Delayed
    
    public var description: String {
        get {
            switch self {
            case Unknown:
                return "Unknown"
            case Ready:
                return "Ready"
            case Delayed:
                return "Delayed"
            }
        }
    }
}

class YSSPlayerView: UIView {
    
    var player: AVPlayer! {
        get {
            let layer: AVPlayerLayer = self.layer as AVPlayerLayer
            return layer.player
        }
        set(newVal) {
            let layer: AVPlayerLayer = self.layer as AVPlayerLayer
            layer.player = newVal
            layer.videoGravity = AVLayerVideoGravityResizeAspect // auto resize
        }
    }
    
    var playerLayer: AVPlayerLayer! {
        get {
            return (self.layer as AVPlayerLayer)
        }
    }
    
    override class func layerClass() -> AnyClass {
        return AVPlayerLayer.self
    }
    
    // MARK - lifecycle
    
    convenience override init() {
        self.init(frame: CGRectZero)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.playerLayer.backgroundColor = UIColor.blackColor().CGColor
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

}

class YSSPlayer: UIViewController {
    
    var player: AVPlayer!
    var playerItem: AVPlayerItem?
    var playerView: YSSPlayerView!
    var playerIndicatorView: UIView!
    
    var playerState: YSSPlayerState!
    private var bufferingStateData: YSSBufferingState!
    var bufferingState: YSSBufferingState! {
        set(newVal){
            self.bufferingStateData = newVal
           /* switch(newVal){
            case .Unknown:
                
            case .Delayed:
                
            case .Ready:
            }*/
        }
        get{
            return self.bufferingStateData
        }
    }
    
    // MARK - lifecycle
    
    override convenience init() {
        self.init(nibName: nil, bundle: nil)
        self.player = AVPlayer()
        self.player.actionAtItemEnd = .Pause
        self.playerState = .Stopped
        self.bufferingState = .Unknown
        
        self.player.addObserver(self, forKeyPath: PlayerRateKey, options: .New | .Old, context: &PlayerObserverContext)
        
        // debug for
        var timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: "debug", userInfo: nil, repeats: true)
    }
    
    func debug() {
        debugPrintln("Player:\(self.playerState), Buffer:\(self.bufferingState)")
    }
    
    deinit {
        self.playerView.player = nil
        
        self.player.removeObserver(self, forKeyPath: PlayerRateKey, context: &PlayerObserverContext)
        
        self.playerView.removeObserver(self, forKeyPath: PlayerReadyForDisplay, context: &PlayerLayerObserverContext)
        
        self.player.pause()
        
        self.setupPlayerItem(nil)
    }
    
    override func loadView() {
        self.playerView = YSSPlayerView(frame: CGRectZero)
        self.playerView.playerLayer.hidden = true
        self.view = self.playerView
        
        self.playerView.layer.addObserver(self, forKeyPath: PlayerReadyForDisplay,
                                                   options: .New | .Old,
                                                   context: &PlayerLayerObserverContext)

    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        
        if self.playerState == .Playing {
            self.stop()
        }
    }
    
    // MARK - Operation
    
    func play(){
        debugPrintln("play")
        self.playerState = .Playing
        self.player.play()
    }
    
    func pause() {
        if self.playerState != .Playing {
            return
        }
        self.player.pause()
        self.playerState = .Paused
    }
    
    func stop() {
        if self.playerState == .Stopped {
            return
        }
        self.player.pause()
        self.playerState = .Stopped
    }
    
    func setupByUrl(urlString: String) {
        let item = AVPlayerItem(URL: NSURL(string: urlString))
        setupPlayerItem(item)
    }
    
    private func setupPlayerItem(let item: AVPlayerItem?) {
        
        if self.playerItem != nil {
            self.playerItem?.removeObserver(self, forKeyPath: PlayerEmptyBufferKey, context: &PlayerItemObserverContext)
            self.playerItem?.removeObserver(self, forKeyPath: PlayerKeepUpKey, context: &PlayerItemObserverContext)
            self.playerItem?.removeObserver(self, forKeyPath: PlayerStatusKey, context: &PlayerItemObserverContext)
        
            NSNotificationCenter.defaultCenter().removeObserver(self, name: AVPlayerItemDidPlayToEndTimeNotification, object: self.playerItem)
            NSNotificationCenter.defaultCenter().removeObserver(self, name: AVPlayerItemFailedToPlayToEndTimeNotification, object: self.playerItem)
            
        }
        
        self.playerItem = item
        
        if item != nil {
            self.playerItem?.addObserver(self, forKeyPath: PlayerEmptyBufferKey, options: .New | .Old, context: &PlayerItemObserverContext)
            self.playerItem?.addObserver(self, forKeyPath: PlayerKeepUpKey, options: .New | .Old, context: &PlayerItemObserverContext)
            self.playerItem?.addObserver(self, forKeyPath: PlayerStatusKey, options: .New | .Old, context: &PlayerItemObserverContext)
  
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "playerItemDidPlayToEndTime:", name: AVPlayerItemDidPlayToEndTimeNotification, object: self.playerItem)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "playerItemFailedToPlayToEndTime:", name: AVPlayerItemFailedToPlayToEndTimeNotification, object: self.playerItem)
            
        }
        
        self.player.replaceCurrentItemWithPlayerItem(self.playerItem)
        
    }
    
    // MARK: NortificationCenter
    
    func playerItemDidPlayToEndTime(aNotification: NSNotification) {
        debugPrintln("playerItemDidPlayToEndTime")
        self.stop()
    }
    
    func playerItemFailedToPlayToEndTime(aNotification: NSNotification) {
        debugPrintln("playerItemFailedToPlayToEndTime")
        self.playerState = .Failed
    }
    
    // MARK: KVO
    
    override func observeValueForKeyPath(keyPath: String,
                                 ofObject object: AnyObject,
                                          change: [NSObject : AnyObject],
                                         context: UnsafeMutablePointer<Void>) {
        switch(keyPath, context) {
        case (PlayerStatusKey, &PlayerItemObserverContext):
            true
        case (PlayerRateKey, &PlayerObserverContext):
            true
        case (PlayerKeepUpKey, &PlayerItemObserverContext):
            debugPrintln("PlayerKeepUp: \(self.playerItem?.playbackLikelyToKeepUp), \(self.playerState)")
            if let item = self.playerItem {
                self.bufferingState = .Ready
                if item.playbackLikelyToKeepUp && self.playerState == .Playing {
                    self.play()
                }
            }
            
            let status = (change[NSKeyValueChangeNewKey] as NSNumber).integerValue as AVPlayerStatus.RawValue
            
            switch(status){
            case AVPlayerStatus.ReadyToPlay.rawValue:
                self.playerView.player = self.player
                self.playerView.playerLayer.hidden = false
            case AVPlayerStatus.Failed.rawValue:
                self.playerState = .Failed
            default:
                true
            }
        case (PlayerEmptyBufferKey, &PlayerItemObserverContext):
            debugPrintln("PlayerEmptyBuffer: \(self.playerItem?.playbackBufferEmpty), \(self.playerState)")
            
            if let item = self.playerItem {
                if item.playbackBufferEmpty {
                    self.bufferingState = .Delayed
                }
            }
            
            let status = (change[NSKeyValueChangeNewKey] as NSNumber).integerValue as AVPlayerStatus.RawValue
            
            switch (status) {
            case AVPlayerStatus.ReadyToPlay.rawValue:
                self.playerView.playerLayer.player = self.player
                self.playerView.playerLayer.hidden = false
            case AVPlayerStatus.Failed.rawValue:
                self.playerState = .Failed
            default:
                true
            }
            
        case (PlayerReadyForDisplay, &PlayerLayerObserverContext):
            if self.playerView.playerLayer.readyForDisplay {
              debugPrintln("PlayerReadyForDisplay: \(self.playerView.playerLayer.readyForDisplay)")
            }
        default:
            debugPrintln("other Event Happended")
            super.observeValueForKeyPath(keyPath,
                    ofObject: object,
                    change: change,
                    context: context)
            
        }
        
    }
    
}



class VideoViewController: UIViewController {
    
    // MARK: view lifecycle
    var player: YSSPlayer?

    override func viewDidLoad() {
        println("view did load")
        super.viewDidLoad()
        self.player = YSSPlayer()
        self.player!.view.frame = self.view.bounds
        self.player?.setupByUrl(ViewControllerVideoPath)
        
        self.view.addSubview(self.player!.view)
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        self.player?.play()
    }

}
