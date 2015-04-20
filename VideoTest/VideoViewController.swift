//
//  VideoViewController.swift
//  VideoTest
//
//  Created by ShoYoshida on 2015/04/13.
//  Copyright (c) 2015年 ShoYoshida. All rights reserved.
//

import UIKit
import AVFoundation

let ViewControllerVideoPath = "http://192.168.59.103/movies/stream.mp4"


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
    
    override func layoutSubviews() {
        if let superview = self.superview {
            self.frame = superview.bounds
        }
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

protocol YSSPlayerDelegate {
    func PlayerReady(player: YSSPlayer)
    func PlayerInterval(player: YSSPlayer)
}

class YSSPlayer: UIViewController {
    
    var delegate: YSSPlayerDelegate?
    
    var player: AVPlayer!
    var playerAsset: AVAsset!
    var playerItem: AVPlayerItem?
    var playerView: YSSPlayerView!
    var playerTimeObserver: AnyObject?
    
    var playerState: YSSPlayerState!
    var bufferingState: YSSBufferingState!
    
    var filepath: String!
    var path: String! {
        get{
            return self.filepath
        }
        set(newVal){
            self.filepath = newVal
            self.setup(newVal)
        }
    }
    
    var duration: NSTimeInterval! {
        get {
            if let playerItem = self.playerItem {
                return CMTimeGetSeconds(playerItem.duration)
            }else{
                return CMTimeGetSeconds(kCMTimeIndefinite)
            }
        }
    }
    var currentTime: NSTimeInterval! {
        get {
            if let time = self.player?.currentTime() {
                return CMTimeGetSeconds(time)
            }else{
                return CMTimeGetSeconds(kCMTimeIndefinite)
            }
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
        
        var timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: "debug", userInfo: nil, repeats: true)
    }
    
    func debug() {
        debugPrintln("Player:\(self.playerState), Buffer:\(self.bufferingState), PlayerItem.KeepUp:\(self.playerItem?.playbackLikelyToKeepUp), PlayerItem.BufferEmpty:\(self.playerItem?.playbackBufferEmpty)")
   
        if let duration = self.playerItem?.duration {
            debugPrintln("Duration: \(CMTimeGetSeconds(duration))")
        }
        if let current = self.player?.currentTime() {
            debugPrintln("Current: \(CMTimeGetSeconds(current))")
        }
    }
    
    deinit {
        println("deinit")
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
        debugPrintln("pause")
        if self.playerState != .Playing {
            return
        }
        self.player.pause()
        self.playerState = .Paused
    }
    
    func stop() {
        debugPrintln("stop")
        if self.playerState == .Stopped {
            return
        }
        self.player.pause()
        self.playerState = .Stopped
    }
    
    func seekTo(time: CMTime) {
        self.player.seekToTime(time)
    }
    
    // Setup Assets
    
    private func setup(urlString: String) {
        
        // Make sure everything is reset beforehand
        if(self.playerState == .Playing){
            self.pause()
        }
        // reset states
        self.bufferingState = .Unknown
        self.setupPlayerItem(nil)
        
        
        var remoteUrl: NSURL? = NSURL(string: urlString)
        if remoteUrl != nil && remoteUrl?.scheme != nil {
            if remoteUrl!.pathExtension == "m3u8" {
                setupByUrl(remoteUrl!)
            }else{
                if let asset = AVURLAsset(URL: remoteUrl, options: .None) {
                    self.setupByAsset(asset)
                }
            }
        } else {
            var localURL: NSURL? = NSURL(fileURLWithPath: urlString)
            if let asset = AVURLAsset(URL: localURL, options: .None) {
                self.setupByAsset(asset)
            }
        }
    }
    
    private func setupByUrl(url: NSURL) {
        debugPrintln("setupByUrl: \(url)")
        let item = AVPlayerItem(URL: url)
        setupPlayerItem(item)
    }
    
    private func setupByAsset(asset: AVURLAsset) {
        debugPrintln("setupByAsset: \(asset)")
        self.playerAsset = asset
        let keys: [String] = [PlayerTracksKey, PlayerPlayableKey, PlayerDurationKey]
        asset.loadValuesAsynchronouslyForKeys(keys, completionHandler: { () -> Void in
            dispatch_sync(dispatch_get_main_queue(), { () -> Void in
                
                for key in keys {
                    var error: NSError?
                    let status = self.playerAsset.statusOfValueForKey(key, error:&error)
                    if status == .Failed {
                        self.playerState = .Failed
                        return
                    }
                }
                
                if self.playerAsset.playable.boolValue == false {
                    self.playerState = .Failed
                    return
                }
                
                let playerItem: AVPlayerItem = AVPlayerItem(asset:self.playerAsset)
                self.setupPlayerItem(playerItem)
                
            })
        })
        
    }
    
    private func setupPlayerItem(let item: AVPlayerItem?) {
        
        if self.playerItem != nil {
            self.playerItem?.removeObserver(self, forKeyPath: PlayerEmptyBufferKey, context: &PlayerItemObserverContext)
            self.playerItem?.removeObserver(self, forKeyPath: PlayerKeepUpKey, context: &PlayerItemObserverContext)
            self.playerItem?.removeObserver(self, forKeyPath: PlayerStatusKey, context: &PlayerItemObserverContext)
        
            NSNotificationCenter.defaultCenter().removeObserver(self, name: AVPlayerItemDidPlayToEndTimeNotification, object: self.playerItem)
            NSNotificationCenter.defaultCenter().removeObserver(self, name: AVPlayerItemFailedToPlayToEndTimeNotification, object: self.playerItem)
            
            self.player.removeTimeObserver(self.playerTimeObserver)
            self.playerTimeObserver = nil
        }
        
        self.playerItem = item
        
        if item != nil {
            self.playerItem?.addObserver(self, forKeyPath: PlayerEmptyBufferKey, options: .New | .Old, context: &PlayerItemObserverContext)
            self.playerItem?.addObserver(self, forKeyPath: PlayerKeepUpKey, options: .New | .Old, context: &PlayerItemObserverContext)
            self.playerItem?.addObserver(self, forKeyPath: PlayerStatusKey, options: .New | .Old, context: &PlayerItemObserverContext)
            
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "playerItemDidPlayToEndTime:", name: AVPlayerItemDidPlayToEndTimeNotification, object: self.playerItem)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "playerItemFailedToPlayToEndTime:", name: AVPlayerItemFailedToPlayToEndTimeNotification, object: self.playerItem)
        
            self.playerTimeObserver = self.player.addPeriodicTimeObserverForInterval(CMTimeMakeWithSeconds(Float64(0.5), Int32(NSEC_PER_SEC)),
                queue: dispatch_get_main_queue(),
                usingBlock: {[weak self] (CMTime) -> Void in
                    if let weakSelf = self {
                        weakSelf.delegate?.PlayerInterval(weakSelf)
                    }
            })
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
                debugPrintln("Duration: \(self.player?.currentItem.duration)")
                self.delegate?.PlayerReady(self)
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


class VideoViewController: UIViewController, YSSPlayerDelegate {
    
    // MARK: view lifecycle
    var player: YSSPlayer?

    @IBOutlet weak var slider: UISlider!
    @IBOutlet weak var vView: UIView!
    @IBOutlet weak var timeLabel: UILabel!
    
    override func viewDidLoad() {
        println("view did load")
        super.viewDidLoad()
        self.player = YSSPlayer()
        debugPrintln(self.vView.bounds)
        self.player?.path = ViewControllerVideoPath // tmp
        self.player?.delegate = self
        self.vView.insertSubview(self.player!.view, atIndex: 0)
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        self.player?.play()
    }
    
    func syncSlider() {
        if let duration = self.player?.currentTime {
            self.slider.setValue(Float(duration), animated: true)
            
            let min = NSString(format: "%d", Int(Int(duration)/60) )
            let sec = NSString(format: "%02d", Int(Int(duration)%60) )
            self.timeLabel.text = "\(min):\(sec)"
        }
    }
    
    // MARK - Actions

    @IBAction func onChange(sender: UISlider) {
        println(sender.value)
        let time = CMTimeMakeWithSeconds(Float64(sender.value), Int32(NSEC_PER_SEC))
        self.player?.seekTo(time)
    }
    
    @IBAction func onStart(sender: AnyObject) {
        self.player?.play()
    }
    @IBAction func onStop(sender: AnyObject) {
        self.player?.stop()
    }
    
    // MARK - YSSPlayerDelegate
    func PlayerReady(player: YSSPlayer) {
        slider.maximumValue =  Float(player.duration)
        debugPrintln("Maximun: \(slider.maximumValue)")
    }
    
    func PlayerInterval(player: YSSPlayer) {
        self.syncSlider()
    }
}
