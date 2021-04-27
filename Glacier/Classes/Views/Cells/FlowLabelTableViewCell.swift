//
//  FlowLabelTableViewCell.swift
//  Glacier
//
//  Created by Andy Friedman on 11/12/20.
//  Copyright © 2020 Glacier. All rights reserved.
//

class FlowLabelTableViewCell:UITableViewCell, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout  {
    @IBOutlet weak var myCollectionView: UICollectionView!
    @IBOutlet weak var collectionViewHeightConstraint: NSLayoutConstraint!
 
    @objc class var flowCell : FlowLabelTableViewCell {
        let cell = Bundle.main.loadNibNamed("FlowLabelTableViewCell", owner: self, options: nil)?.last
        return cell as! FlowLabelTableViewCell
    }
    
    var myteams:Array<Any>?
    @objc public func updateWithTeams(_ teams:Array<Any>) { 
        self.myteams = teams
        self.myCollectionView.reloadData()
        didUpdateCollectionView()
    }
 
    let cellReuseId = "CollectionViewCell"
    override func awakeFromNib() {
        super.awakeFromNib()
        //TODO: need to setup collection view flow layout
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.scrollDirection = .vertical
        flowLayout.itemSize = CGSize(width: 100, height: 40)
        flowLayout.estimatedItemSize = flowLayout.itemSize
        flowLayout.minimumLineSpacing = 5.0
        flowLayout.minimumInteritemSpacing = 5.0
        self.myCollectionView.collectionViewLayout = flowLayout
        self.myCollectionView.isScrollEnabled = false
        //Comment if you set Datasource and delegate in .xib
        self.myCollectionView.dataSource = self
        self.myCollectionView.delegate = self
        
        //————————register the xib for collection view cell————————————————
        let cellNib = UINib(nibName: "CustomCollectionViewCell", bundle: nil)
        self.myCollectionView.register(cellNib, forCellWithReuseIdentifier: cellReuseId)
    }
    
    @objc public class func cellIdentifier() -> String {
        return "FlowLabelTableViewCell"
    }
    
    @objc public func getHeightConstraint() -> CGFloat {
        return collectionViewHeightConstraint.constant
    }
    
    open func didUpdateCollectionView() {
        // Layout and resize to match content
        self.myCollectionView.collectionViewLayout.invalidateLayout()
        self.myCollectionView.collectionViewLayout.prepare()
        self.myCollectionView.setNeedsLayout()
        self.myCollectionView.layoutIfNeeded()
        //To get the content size after reload, try to call collectionViewContentSize of the layout object. It works for me.
        //let flowheight = self.myCollectionView.collectionViewLayout.collectionViewContentSize.height
        let height = self.myCollectionView.contentSize.height
        collectionViewHeightConstraint.constant = height
    }
 
    //MARK: Collection view datasource and Delegate
 
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if let teams = self.myteams {
            return teams.count
        } else {
            return 1
        }
    }
 
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
 
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseId, for: indexPath) as? CustomCollectionViewCell
        if (self.myteams == nil || self.myteams?.count == 0) {
            cell?.updateCellWithTeam(name: "No teams available")
        } else {
            if let team = self.myteams?[indexPath.item] as? String {
                cell?.updateCellWithTeam(name: team)
            }
        }
        return cell!
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
            return UIEdgeInsetsMake(10, 10, 0, 10)
    }
}

class CustomCollectionViewCell: UICollectionViewCell {
    //creates new cell form xib
    class var CustomCell : CustomCollectionViewCell {
        let cell = Bundle.main.loadNibNamed("CustomCollectionViewCell", owner: self, options: nil)?.last
        return cell as! CustomCollectionViewCell
    }
    
    var teamName:String? //to hold image name
    @IBOutlet weak var cellTeamView: InsetsLabel!
    func updateCellWithTeam(name:String) {
        self.teamName = name
        self.cellTeamView.text = teamName
        if #available(iOS 13.0, *) {
            self.cellTeamView.layer.borderColor = UIColor.label.cgColor
        }
        self.cellTeamView.contentInsets = UIEdgeInsetsMake(0, 10, 0, 10)
    }
    
    //call once successful loading of the cell
    override func awakeFromNib() {
        super.awakeFromNib()
    }
}
