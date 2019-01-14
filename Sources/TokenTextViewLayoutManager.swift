// Copyright © 2017 Hootsuite. All rights reserved.

import Foundation
import UIKit

class TokenTextViewLayoutManager: NSLayoutManager {

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<CGRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: UIColor) {
        // FIXME: check attributes
        for i in 0..<rectCount {
			// This prevents the token ui from overlapping with the previous character.
            let backgroundRect = rectArray[i].inset(by: UIEdgeInsets(top: 2, left: -6, bottom: 2, right: 0))
            let path = UIBezierPath(roundedRect: backgroundRect, cornerRadius: 20)
            path.fill()
            path.stroke()
        }
        color.set()
    }

}
