//
//  WarningsViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2022-04-11.
//
//  ---------------------------------------------------------------------------
//
//  © 2022-2023 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit

final class WarningsViewController: NSSplitViewController {
    
    // MARK: Lifecycle
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.splitView.isVertical = false
        
        self.addChild(NSStoryboard(name: "IncompatibleCharactersView").instantiateInitialController()!)
        self.addChild(NSStoryboard(name: "InconsistentLineEndingsView").instantiateInitialController()!)
        self.updateRepresentedObject()
        
        // set accessibility
        self.view.setAccessibilityLabel(String(localized: "Warnings"))
    }
    
    
    /// deliver passed-in document instance to child view controllers
    override var representedObject: Any? {
        
        didSet {
            self.updateRepresentedObject()
        }
    }
    
    
    // MARK: Private Methods
    
    /// Update representedObjects in the child views.
    private func updateRepresentedObject() {
        
        for item in self.splitViewItems {
            item.viewController.representedObject = representedObject
        }
    }
}
