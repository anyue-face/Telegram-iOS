import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit
internal import TelegramApi


public struct AppUpdateInfo: Equatable {
    public let blocking: Bool
    public let version: String
    public let text: String
    public let entities: [MessageTextEntity]
    /// Where the update is installed from, when the server names a page (`help.appUpdate.url`).
    /// An enterprise-signed build is installed from a web page rather than the App Store.
    public let url: String?
    
    public init(blocking: Bool, version: String, text: String, entities: [MessageTextEntity], url: String?) {
        self.blocking = blocking
        self.version = version
        self.text = text
        self.entities = entities
        self.url = url
    }
}

extension AppUpdateInfo {
    init?(apiAppUpdate: Api.help.AppUpdate) {
        switch apiAppUpdate {
            case let .appUpdate(appUpdateData):
                let (flags, version, text, entities) = (appUpdateData.flags, appUpdateData.version, appUpdateData.text, appUpdateData.entities)
                self.blocking = (flags & (1 << 0)) != 0
                self.version = version
                self.text = text
                self.entities = messageTextEntitiesFromApiEntities(entities)
                if let url = appUpdateData.url, !url.isEmpty {
                    self.url = url
                } else {
                    self.url = nil
                }
            case .noAppUpdate:
                return nil
        }
    }
}

func managedAppUpdateInfo(network: Network, stateManager: AccountStateManager) -> Signal<Never, NoError> {
    let poll = network.request(Api.functions.help.getAppUpdate(source: ""))
    |> retryRequest
    |> mapToSignal { [weak stateManager] result -> Signal<Never, NoError> in
        let updated = AppUpdateInfo(apiAppUpdate: result)
        stateManager?.modifyAppUpdateInfo { _ in
            return updated
        }
        return .complete()
    }
    
    return (poll |> then(.complete() |> suspendAwareDelay(12.0 * 60.0 * 60.0, queue: Queue.concurrentDefaultQueue()))) |> restart
}
