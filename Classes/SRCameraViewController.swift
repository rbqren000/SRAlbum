//
//  SRCameraViewController.swift
//  SRAlbum
//
//  Created by 施峰磊 on 2021/8/2.
//  Copyright © 2021 施峰磊. All rights reserved.
//

import UIKit
import Photos
import SRToast

@objc public enum SRCameraType:Int{
    case Photo//普通拍照
    case Video//视频
}

class SRCameraViewController: UIViewController{
    @IBOutlet weak var cameraView: SRCameraView!
    @IBOutlet weak var playerView: SRPlayerView!
    @IBOutlet weak var qhBtn: UIButton!
    @IBOutlet weak var flashBtn: UIButton!
    @IBOutlet weak var time: UILabel!
    @IBOutlet weak var pzBtn: UIButton!
    
    
    open var fileName:String?
    private var vedioUrl:URL?
    
    deinit {
//        print("Kill")
        SRAlbumData.free();
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.configerView()
        self.cameraView.install(isRectangleDetection: is_rectangle_detection) { [weak self] in
            self?.cameraView.startRunning()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: true)
    }
    
    private func configerView(){
        self.flashBtn.isHidden = camera_type == .Video
        self.time.isHidden = camera_type == .Photo
        if camera_type == .Video{
            self.qhBtn.isHidden = false
            self.cameraView.cameraModeType = .Video
            self.pzBtn.setImage(UIImage.init(named: "sr_videotape_un_icon", in: bundle, compatibleWith: nil), for: .normal)
        }else{
            self.qhBtn.isHidden = is_rectangle_detection
            self.cameraView.cameraModeType = .Photo
            self.pzBtn.setImage(UIImage.init(named: "sr_photograph_icon", in: bundle, compatibleWith: nil), for: .normal)
        }
        if self.cameraView.flashMode == .auto {
            self.flashBtn.setImage(UIImage.init(named: "sr_camera_flash_auto_icon", in: bundle, compatibleWith: nil), for: .normal)
        }else if self.cameraView.flashMode == .on {
            self.flashBtn.setImage(UIImage.init(named: "sr_camera_flash_on_icon", in: bundle, compatibleWith: nil), for: .normal)
        }else if self.cameraView.flashMode == .off {
            self.flashBtn.setImage(UIImage.init(named: "sr_camera_flash_close_icon", in: bundle, compatibleWith: nil), for: .normal)
        }
        self.cameraView.imageResult = {[weak self](orgimage:UIImage?, _error:Error?) in
            if orgimage != nil {
                if is_eidt {
                    self?.cameraView.stopRunning()
                    let eidtAsset = EditorAsset.init(type: EditorAsset.AssetType.image(orgimage!), result: nil)
                    var config: EditorConfiguration = .init()
                    if !SRAlbumData.sharedInstance.eidtSize.equalTo(.zero){
                        config.cropSize.aspectRatio = SRAlbumData.sharedInstance.eidtSize
                        config.cropSize.isFixedRatio = true
                        config.cropSize.aspectRatios = []
                    }
                    config.toolsView.toolOptions.remove(at: 2)
                    let vc = EditorViewController(eidtAsset, config: config)
                    vc.finishHandler = {[weak self] (eidtAsset, editorViewController) in
                        if eidtAsset.contentType == .image {
                            switch eidtAsset.type {
                            case .image(let image):
                                if SRAlbumData.sharedInstance.isZip{
                                    let hub = self?.view.showHub(value: "处理中")
                                    DispatchQueue.global().async {//图片压缩
                                        let imgData = SRHelper.imageZip(sourceImage:image, maxSize: max_size)
                                        DispatchQueue.main.async {
                                            hub?.remove()
                                            vc.dismiss(animated: false)
                                            let infoData = SRFileInfoData.init(fileType: .Data, nil, imgData, nil)
                                            SRAlbumData.sharedInstance.completeHandle?(infoData)
                                            self?.dismiss(animated: true, completion: nil)
                                        }
                                    }
                                }else{
                                    DispatchQueue.main.async {
                                        vc.dismiss(animated: false)
                                        let infoData = SRFileInfoData.init(fileType: .Image, image, nil, nil)
                                        SRAlbumData.sharedInstance.completeHandle?(infoData)
                                        self?.dismiss(animated: true, completion: nil)
                                    }
                                }
                                break
                            default:
                                break
                            }
                        }
                    }
    //                vc.delegate = self
                    self?.present(vc, animated: true, completion: nil)
                }else{
                    if SRAlbumData.sharedInstance.isZip{
                        let hub = self?.view.showHub(value: "处理中")
                        DispatchQueue.global().async {//图片压缩
                            let imgData:Data = SRHelper.imageZip(sourceImage:orgimage!, maxSize: max_size)
                            DispatchQueue.main.async {
                                hub?.remove()
                                let infoData = SRFileInfoData.init(fileType: .Data, nil, imgData, nil)
                                SRAlbumData.sharedInstance.completeHandle?(infoData)
                            }
                        }
                    }else{
                        let infoData = SRFileInfoData.init(fileType: .Image, orgimage, nil, nil)
                        SRAlbumData.sharedInstance.completeHandle?(infoData)
                    }
                }
            }
            if is_eidt == false {
                self?.dismiss(animated: true, completion: nil)
            }
        }
        self.cameraView.recordingResult = {[weak self](timeValue:Int, fileUrl:URL?) in
            self?.time.text = SRHelper.convertTimeSecond(timeSecond: TimeInterval(timeValue))
            if fileUrl != nil {
                self?.vedioUrl = fileUrl
                self?.playerView.isHidden = false
                self?.playerView.play(playUrl: fileUrl!)
            }
        }
    }

    @IBAction func pzAction(_ sender: UIButton) {
        if camera_type == .Video{
            if self.cameraView.isRecording{
                self.cameraView.stopRecording()
                sender.isSelected = false
            }else{
                self.cameraView.startRecording(fileURL: URL.init(fileURLWithPath: videoTemporaryDirectory(fileName: nil)))
                sender.isSelected = true
            }
        }else{
            self.cameraView.photographOperation()
        }
    }
    
    @IBAction func swithCameraAction(_ sender: UIButton) {
        let type = self.cameraView.swithCamera()
        if camera_type == .Photo{
            self.flashBtn.isHidden = type == 2
        }else{
            self.flashBtn.isHidden = true
        }
    }

    @IBAction func flashAction(_ sender: UIButton) {
        if self.cameraView.flashMode == .off {
            self.cameraView.flashMode = .on
            self.flashBtn.setImage(UIImage.init(named: "sr_camera_flash_on_icon", in: bundle, compatibleWith: nil), for: .normal)
        }else if self.cameraView.flashMode == .on {
            self.cameraView.flashMode = .auto
            self.flashBtn.setImage(UIImage.init(named: "sr_camera_flash_auto_icon", in: bundle, compatibleWith: nil), for: .normal)
        }else if self.cameraView.flashMode == .auto {
            self.cameraView.flashMode = .off
            self.flashBtn.setImage(UIImage.init(named: "sr_camera_flash_close_icon", in: bundle, compatibleWith: nil), for: .normal)
        }
    }
    @IBAction func closeAction(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func cancelPlayAction(_ sender: UIButton) {
        self.playerView.stop()
        self.playerView.isHidden = true
        SRHelper.cleanMov(url: self.vedioUrl!)
        self.vedioUrl = nil
    }
    
    @IBAction func selectPlayAction(_ sender: UIButton) {
        let infoData = SRFileInfoData.init(fileType: .FileUrl, nil, nil, self.vedioUrl)
        SRAlbumData.sharedInstance.completeHandle?(infoData)
        self.dismiss(animated: true) {[weak self] in
            self?.vedioUrl = nil
        }
    }
    
    override var shouldAutorotate: Bool{
        return true
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask{
        return UIInterfaceOrientationMask.portrait
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation{
        return UIInterfaceOrientation.portrait
    }
}
