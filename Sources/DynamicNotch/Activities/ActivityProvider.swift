import Foundation

public protocol ActivityProvider: AnyObject {
    var providerId: String { get }
    func start()
    func stop()
}
