//
//  SRAlbumController.swift
//  SRAlbum
//
//  Created by 施峰磊 on 2020/1/17.
//  Copyright © 2020 施峰磊. All rights reserved.
//

import UIKit
import Photos

@objc public enum SRAssetType:Int{
    case None
    case Photo
    case Video
}

class SRAlbumController: UIViewController, UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout, SRAlbumImageCellDelegate , SRAlbumBrowseControllerDelegate{
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var previewButton: UIButton!
    @IBOutlet weak var zipButton: UIButton!
    private var topButton:TopSwitchButton? = TopSwitchButton.createTopSwitchButton()
    private var groupView:GroupView? = GroupView.createGroupView();
    
    
    //MARK: - 属性
    //TODO: 相册组列表
    var albumsCollection = Array<PHAssetCollection>.init();
    //TODO: 每一个Item的尺寸
    private let itemWidth:CGFloat = ((UIScreen.main.bounds.size.width - 2.0*5.0)/4.0)-0.1;
    //TODO: 当前的相册组
    private var collection:PHAssetCollection?
    
    
    //MARK: - 生命周期
    deinit {
//        print("相册Kill")
        SRAlbumData.free();
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.configerView()
        self.addViews()
        self.getDatas()
        _ = self.isCanSend()
        _ = self.isCanPreview()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        self.zipButton.isSelected = !SRAlbumData.sharedInstance.isZip
        self.navigationController?.setNavigationBarHidden(false, animated: false)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews();
        self.groupView?.frame = self.view.bounds;
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle{
        return .lightContent
    }
    //MARK: - 操作
    func addViews() -> Void {
        self.view.addSubview(self.groupView!);
    }
    
    func configerView() -> Void {
        self.navigationItem.leftBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAction))
        self.topButton?.frame = CGRect.init(x: 0, y: 0, width: 115, height: 32);
        self.topButton?.addTarget(self, action: #selector(switchAlbumsGroupAction(_:)), for: .touchUpInside);
        self.navigationItem.titleView = self.topButton;
        let layout = UICollectionViewFlowLayout();
        layout.scrollDirection = .vertical;
        self.collectionView.collectionViewLayout = layout;
        self.collectionView.alwaysBounceVertical = true;
        self.collectionView.register(UINib.init(nibName: "SRAlbumImageCell", bundle: bundle), forCellWithReuseIdentifier: "SRAlbumImageCell");
    }
    
    
    func getDatas() -> Void {
        self.queryImages()
        if #available(iOS 14.0, *){
            let authorStatus = PHPhotoLibrary.authorizationStatus(for: PHAccessLevel.readWrite)
            if authorStatus == .limited{
                
            }
        }
    }
    
    private func queryImages(){
        self.collectionView.alpha = 0;
        self.loadAlbumsCollection { [weak self](results) in
            self?.groupView?.albumsCollection = results;
            self?.collection = results.first;
            self?.topButton?.titleLabel.text = self?.collection!.localizedTitle;
            self?.albumsCollection.append(contentsOf: results);
            self?.collectionView.reloadData();
            if self?.collection?.assets.count ?? 0 > 0{
                DispatchQueue.main.async {
                    UIView.animate(withDuration: 0.2) {
                        self?.collectionView.alpha = 1.0;
                    }
                    self?.collectionView.scrollToItem(at: IndexPath.init(row: self!.collection!.assets.count-1, section: 0), at: .bottom, animated: false)
                }
            }else{
                self?.collectionView.alpha = 1.0;
            }
        }
    }
    
    func isCanSend() -> Bool{
        self.sendButton.isEnabled = SRAlbumData.sharedInstance.sList.count>0;
        return self.sendButton.isEnabled
    }
    
    func isCanPreview() -> Bool{
        self.previewButton.isSelected = SRAlbumData.sharedInstance.sList.count == 0;
        return !self.previewButton.isSelected
    }
    
    /// TODO: 界面刷新
    /// - Parameters:
    ///   - data: 资源
    ///   - indexPath: 索引
    ///   - cell: cell
    func reloadAlbum(data:PHAsset, indexPath:IndexPath, cell:SRAlbumImageCell) -> Bool {
        var isAdd = false
        
        if let index = SRAlbumData.sharedInstance.sList.firstIndex(of: data) {
            SRAlbumData.sharedInstance.sList.remove(at: index);
            cell.isSelected = false;
            isAdd = false
        }else{
            if is_eidt && max_count == 1 && data.isPhoto() {//限制一张图片并且要求编辑的，则直接编辑图片
                isAdd = true
                _ = data.requestOriginalImage { [weak self] imageData, info in
                    if let image = UIImage.init(data: imageData!) {
                        let eidtAsset = EditorAsset.init(type: EditorAsset.AssetType.image(image), result: nil)
                        var config: EditorConfiguration = .init()
                        if !SRAlbumData.sharedInstance.eidtSize.equalTo(.zero){
                            config.cropSize.aspectRatio = SRAlbumData.sharedInstance.eidtSize
                            config.cropSize.isFixedRatio = true
                            config.cropSize.aspectRatios = []
                        }
                        config.toolsView.toolOptions.remove(at: 2)
                        
                        let vc = EditorViewController(eidtAsset, config: config)
                        vc.modalPresentationStyle = .fullScreen
                        vc.finishHandler = {[weak self] (eidtAsset, editorViewController) in
                            if eidtAsset.contentType == .image {
                                switch eidtAsset.type {
                                case .image(let image):
                                    if SRAlbumData.sharedInstance.isZip {
                                        let hub = self?.view.showHub(value: "处理中")
                                        DispatchQueue.global().async {
                                            data.editedPic = image;
                                            DispatchQueue.main.async {
                                                hub?.remove()
                                                SRAlbumData.sharedInstance.completeFilesHandle?([SRFileInfoData.init(fileType: .Image, image, nil, nil)])
                                                vc.dismiss(animated: false)
                                                self?.cancelAction()
                                            }
                                        }
                                    }else{
                                        data.editedPic = image
                                        SRAlbumData.sharedInstance.completeFilesHandle?([SRFileInfoData.init(fileType: .Image, image, nil, nil)])
                                        vc.dismiss(animated: false)
                                        self?.cancelAction()
                                    }
                                    break
                                default:
                                    break
                                }
                            }
                        }
//                        vc.delegate = self
                        self?.present(vc, animated: true, completion: nil)
                    }
                }
            }else{
                if SRAlbumData.sharedInstance.sList.count >= max_count {
                    SRAlbumTip.sharedInstance.show(content: "最多只能选\(max_count)个！")
                }else{
                    SRAlbumData.sharedInstance.sList.append(data)
                    cell.isSelected = true;
                    isAdd = true
                }
            }
        }
        for visibleCell in collectionView.visibleCells {
            let cell:SRAlbumImageCell = visibleCell as! SRAlbumImageCell;
            cell.configer(index: (SRAlbumData.sharedInstance.sList.firstIndex(of: cell.data!) ?? -1) + 1)
        }
        collectionView.reloadItems(at: [indexPath]);
        _ = self.isCanSend();
        _ = self.isCanPreview();
        return isAdd;
    }
    
    /// TODO: 发送图片
    func sendAlbum() -> Void {
        asynchronousHanldAssent()
    }

    
    /// TODO: 处理文件
    func asynchronousHanldAssent() -> Void {
        let hub = self.view.showHub(value: "处理中")
        // 创建调度组
        let workingGroup = DispatchGroup()
        // 创建多列
        let workingQueue = DispatchQueue(label: "hanldAssent")
        var results:[Any] = []
        if is_sort{
            results.append(contentsOf: SRAlbumData.sharedInstance.sList)
        }
        var index = 0
        for asset in SRAlbumData.sharedInstance.sList {
            if is_sort{
                asset.index = index
                index += 1
            }
            workingGroup.enter()
            workingQueue.async {
                if asset.isVideo(){
                    let options = PHVideoRequestOptions.init()
                    options.isNetworkAccessAllowed = true;
                    PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { (vedioAsset, audioMix, info) in
                        if let urlAsset = vedioAsset as? AVURLAsset{
                            SRHelper.videoZip(sourceUrl: urlAsset.url, tagerUrl: nil) { url in
                                let infoData = SRFileInfoData.init(fileType: .FileUrl, nil, nil, url)
                                if is_sort{
                                    results[asset.index] = infoData
                                }else{
                                    results.append(infoData)
                                }
                                workingGroup.leave()
                            }
                        }
                    }
                }else{
                    if asset.editedPic == nil {
                        _=asset.requestOriginalImage(resizeMode: .none) { (imageData, info) in
                            if asset.isGif() {
                                let infoData = SRFileInfoData.init(fileType: .GifData, nil, imageData, nil)
                                results.append(infoData)
                            }else{
                                if SRAlbumData.sharedInstance.isZip {
                                    let zipData = SRHelper.imageZip(sourceImage:UIImage.init(data: imageData!)!, maxSize: max_size)
                                    let infoData = SRFileInfoData.init(fileType: .Data, nil, zipData, nil)
                                    if is_sort{
                                        results[asset.index] = infoData
                                    }else{
                                        results.append(infoData)
                                    }
                                }else{
                                    let img = UIImage.init(data: imageData!)!
                                    let infoData = SRFileInfoData.init(fileType: .Image, img, nil, nil)
                                    if is_sort{
                                        results[asset.index] = infoData
                                    }else{
                                        results.append(infoData)
                                    }
                                }
                            }
                            workingGroup.leave()
                        }
                    }else{
                        if SRAlbumData.sharedInstance.isZip {
                            let zipData = SRHelper.imageZip(sourceImage:asset.editedPic!, maxSize: max_size)
                            let infoData = SRFileInfoData.init(fileType: .Data, nil, zipData, nil)
                            if is_sort{
                                results[asset.index] = infoData
                            }else{
                                results.append(infoData)
                            }
                            
                        }else{
                            let infoData = SRFileInfoData.init(fileType: .Image, asset.editedPic!, nil, nil)
                            if is_sort{
                                results[asset.index] = infoData
                            }else{
                                results.append(infoData)
                            }
                        }
                        workingGroup.leave()
                    }
                }
            }
        }
        // 调度组里的任务都执行完毕
        workingGroup.notify(queue: workingQueue) {
            DispatchQueue.main.async {
                hub.remove()
                SRAlbumData.sharedInstance.completeFilesHandle?(results as! [SRFileInfoData])
                self.cancelAction()
            }
        }
    }
    
    
    //MARK: - 点击事件
    /// TODO: 取消
    @objc func cancelAction() -> Void {
        self.dismiss(animated: true) {
            
        }
    }
    
    /// TODO: 顶部选择
    /// - Parameter sender: 按钮
    @objc func switchAlbumsGroupAction(_ sender: UIControl) -> Void {
        sender.isSelected  = !sender.isSelected;
        if sender.isSelected {
            self.groupView?.show(result: { [weak self](assetCollection) in
                self?.collection = assetCollection;
                self?.topButton?.titleLabel.text = self?.collection!.localizedTitle;
                self?.topButton?.isSelected = false
                self?.collectionView.reloadData();
                if self?.collection?.assets.count ?? 0 > 0{
                    DispatchQueue.main.async {
                        self?.collectionView.scrollToItem(at: IndexPath.init(row: self!.collection!.assets.count-1, section: 0), at: .bottom, animated: false)
                    }
                }
            }, cancel: {[weak self] in
                self?.topButton?.isSelected = false
            })
        }else{
            self.groupView?.hiddenView()
        }
    }

    /// TODO: 预览
    /// - Parameter sender: 按钮
    @IBAction func previewAction(_ sender: UIButton) {
        if self.isCanPreview() {
            let vc:SRAlbumBrowseController = SRAlbumBrowseController.init(nibName: "SRAlbumBrowseController", bundle: bundle);
            vc.delegate = self;
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    /// TODO: 发送
    /// - Parameter sender: 按钮
    @IBAction func sandAction(_ sender: UIButton) {
        sendAlbum();
    }
    
    /// TODO: 是否压缩
    /// - Parameter sender: 按钮
    @IBAction func zipAction(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected;
        SRAlbumData.sharedInstance.isZip = !sender.isSelected
    }
    
    // MARK:- UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize.init(width: itemWidth, height: itemWidth );
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets.init(top: 2, left: 2, bottom: 2, right: 2);
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 2;
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 2;
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.collection?.assets.count ?? 0;
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let data = self.collection!.assets[indexPath.row]
        let cell:SRAlbumImageCell = collectionView.dequeueReusableCell(withReuseIdentifier: "SRAlbumImageCell", for: indexPath) as! SRAlbumImageCell;
        cell.delegate = self;
        cell.indexPath = indexPath;
        cell.data = data;
        cell.configer(index: (SRAlbumData.sharedInstance.sList.firstIndex(of: data) ?? -1) + 1)
        return cell;
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let vc:SRAlbumBrowseController = SRAlbumBrowseController.init(nibName: "SRAlbumBrowseController", bundle: bundle);
        vc.delegate = self;
        vc.collection = self.collection;
        vc.indexPath = indexPath;
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    //MARK: - SRAlbumBrowseControllerDelegate
    /// TODO: 浏览器已经选择或者取消了资源
    /// - Parameters:
    ///   - data: 资源
    ///   - indexPath: 索引
    func reloadAlbumData(data:PHAsset, indexPath:IndexPath?) -> Bool {
        var index_path:IndexPath;
        if indexPath != nil {
            index_path = indexPath!
        }else{
            index_path = IndexPath.init(row: self.collection!.assets.index(of: data), section: 0)
        }
        if let cell:SRAlbumImageCell = collectionView.cellForItem(at: index_path) as? SRAlbumImageCell {
             return self.reloadAlbum(data: data, indexPath:index_path, cell: cell);
        }else{
            var isAdd = false
            if let index = SRAlbumData.sharedInstance.sList.firstIndex(of: data) {
                SRAlbumData.sharedInstance.sList.remove(at: index);
                isAdd = false
            }else{
                if is_eidt && max_count == 1 && data.isPhoto() {//限制一张图片并且要求编辑的，则直接编辑图片
                    _ = data.requestOriginalImage { [weak self] imageData, info in
                        if let image = UIImage.init(data: imageData!) {
                            let eidtAsset = EditorAsset.init(type: EditorAsset.AssetType.image(image), result: nil)
                            var config: EditorConfiguration = .init()
                            if !SRAlbumData.sharedInstance.eidtSize.equalTo(.zero){
                                config.cropSize.aspectRatio = SRAlbumData.sharedInstance.eidtSize
                                config.cropSize.isFixedRatio = true
                                config.cropSize.aspectRatios = []
                            }
                            config.toolsView.toolOptions.remove(at: 2)
                            let vc = EditorViewController(eidtAsset, config: config)
                            vc.modalPresentationStyle = .fullScreen
                            vc.finishHandler = {[weak self] (eidtAsset, editorViewController) in
                                if eidtAsset.contentType == .image {
                                    switch eidtAsset.type {
                                    case .image(let image):
                                        if SRAlbumData.sharedInstance.isZip {
                                            let hub = self?.view.showHub(value: "处理中")
                                            DispatchQueue.global().async {
                                                data.editedPic = image;
                                                DispatchQueue.main.async {
                                                    hub?.remove()
                                                    SRAlbumData.sharedInstance.completeFilesHandle?([SRFileInfoData.init(fileType: .Image, image, nil, nil)])
                                                    vc.dismiss(animated: false)
                                                    self?.cancelAction()
                                                }
                                            }
                                        }else{
                                            data.editedPic = image
                                            SRAlbumData.sharedInstance.completeFilesHandle?([SRFileInfoData.init(fileType: .Image, image, nil, nil)])
                                            vc.dismiss(animated: false)
                                            self?.cancelAction()
                                        }
                                        break
                                    default:
                                        break
                                    }
                                }
                            }
//                            vc.delegate = self
                            self?.present(vc, animated: true, completion: nil)
                        }
                    }
                    isAdd = true
                }else{
                    if SRAlbumData.sharedInstance.sList.count >= max_count {
                        SRAlbumTip.sharedInstance.show(content: "最多只能选\(max_count)个！")
                        isAdd = false
                    }else{
                        SRAlbumData.sharedInstance.sList.append(data)
                        isAdd = true
                    }
                }
            }
            self.collectionView.reloadData()
            return isAdd
        }
    }
    
    /// TODO: 图片已经被编辑了
    /// - Parameters:
    ///   - data: 资源
    func eidtFinish(data:PHAsset) -> Void{
        self.collectionView.reloadData()
    }
    
    
    /// TODO:资源发送
    func sendAsset() -> Void{
        self.sendAlbum()
    }
    
    //MARK: - SRAlbumImageCellDelegate
    /// TODO: 点击选择了资源
    /// - Parameters:
    ///   - data: 资源
    ///   - indexPath: 索引
    ///   - cell: cell视图
    func didClickSeletcImage(data:PHAsset, indexPath:IndexPath, cell:SRAlbumImageCell) -> Void{
        _ = self.reloadAlbum(data: data, indexPath:indexPath, cell: cell);
    }
    
    //MARK: - 获取相册内容
    
    /// TODO: 获取相册组
    /// - Parameter result: 相册组
    func loadAlbumsCollection(result:((Array<PHAssetCollection>) -> ())?) -> Void {
        var results:Array<PHAssetCollection> = Array<PHAssetCollection>.init()
        
        let assetCollections:PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil);
        if assetCollections.count > 0 {
            results.append(contentsOf: assetCollections.objects(at: IndexSet.init(integersIn: 0 ... assetCollections.count-1)));
        }
        //所有图片移动的第一位
        var userCollection:PHAssetCollection?
        var index = 0
        for collection in results {
            if collection.assetCollectionSubtype == .smartAlbumUserLibrary {
                userCollection = collection
                break;
            }
            index += 1;
        }
        if userCollection != nil {
            results.remove(at: index);
            results.insert(userCollection!, at: 0)
        }
        result?(results)
    }

}
