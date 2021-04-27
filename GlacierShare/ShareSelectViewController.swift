//
//  ShareSelectViewController.swift
//  Floop
//
//  Created by Scott Fister on 4/24/17.
//  Copyright © 2017 Scott Fister. All rights reserved.
//
import UIKit

protocol ShareSelectViewControllerDelegate: class {
    func selected(conversation: Conversation)
}

class ShareSelectViewController: UIViewController {
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: self.view.frame)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Identifiers.ConversationCell)
        return tableView
    }()
    var userConversations = [Conversation]()
    weak var delegate: ShareSelectViewControllerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
        title = "Select Conversation"
        view.addSubview(tableView)
    }
}

extension ShareSelectViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return userConversations.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Identifiers.ConversationCell, for: indexPath)
        cell.textLabel?.text = userConversations[indexPath.row].name
        cell.backgroundColor = .clear
        return cell
    }
}

extension ShareSelectViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        delegate?.selected(conversation: userConversations[indexPath.row])
    }
}

private extension ShareSelectViewController {
    struct Identifiers {
        static let ConversationCell = "conversationCell"
    }
}
