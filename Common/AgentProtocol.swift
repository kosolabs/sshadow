import Foundation
import SwiftLibSSH

public enum OnExists: Codable {
    case fail
    case succeed
}

public enum OnParentNotExists: Codable {
    case fail
    case create
}

public enum AgentRequest: Codable {
    case name(NameRequest)
    case child(ChildRequest)
    case parent(ParentRequest)
    case pathForItem(PathForItemRequest)
    case pathForChild(PathForChildRequest)
    case info(InfoRequest)
    case list(ListRequest)
    case exists(ExistsRequest)
    case setAttributes(SetAttributesRequest)
    case createDirectory(CreateDirectoryRequest)
    case move(MoveRequest)
    case removeFile(RemoveFileRequest)
    case removeDirectory(RemoveDirectoryRequest)
}

public struct NameRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct ChildRequest: Codable {
    public let domainId: UUID
    public let parentId: String
    public let path: String
    public let ifNotExists: DomainDB.OnNotExists

    public init(
        domainId: UUID,
        parentId: String,
        path: String,
        ifNotExists: DomainDB.OnNotExists
    ) {
        self.domainId = domainId
        self.parentId = parentId
        self.path = path
        self.ifNotExists = ifNotExists
    }
}

public struct ParentRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct PathForItemRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct PathForChildRequest: Codable {
    public let domainId: UUID
    public let name: String
    public let parentId: String

    public init(domainId: UUID, name: String, parentId: String) {
        self.domainId = domainId
        self.name = name
        self.parentId = parentId
    }
}

public struct InfoRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct ListRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct ExistsRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct SetAttributesRequest: Codable {
    public let domainId: UUID
    public let itemId: String
    public let permissions: mode_t?
    public let accessTime: Date?
    public let modifyTime: Date?

    public init(
        domainId: UUID,
        itemId: String,
        permissions: mode_t?,
        accessTime: Date?,
        modifyTime: Date?
    ) {
        self.domainId = domainId
        self.itemId = itemId
        self.permissions = permissions
        self.accessTime = accessTime
        self.modifyTime = modifyTime
    }
}

public struct CreateDirectoryRequest: Codable {
    public let domainId: UUID
    public let itemId: String
    public let mode: mode_t
    public let ifExists: OnExists

    public init(
        domainId: UUID,
        itemId: String,
        mode: mode_t,
        ifExists: OnExists
    ) {
        self.domainId = domainId
        self.itemId = itemId
        self.mode = mode
        self.ifExists = ifExists
    }
}

public struct MoveRequest: Codable {
    public let domainId: UUID
    public let itemId: String
    public let newParentId: String
    public let newName: String
    public let ifParentNotExists: OnParentNotExists

    public init(
        domainId: UUID,
        itemId: String,
        newParentId: String,
        newName: String,
        ifParentNotExists: OnParentNotExists
    ) {
        self.domainId = domainId
        self.itemId = itemId
        self.newParentId = newParentId
        self.newName = newName
        self.ifParentNotExists = ifParentNotExists
    }
}

public struct RemoveFileRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public struct RemoveDirectoryRequest: Codable {
    public let domainId: UUID
    public let itemId: String

    public init(domainId: UUID, itemId: String) {
        self.domainId = domainId
        self.itemId = itemId
    }
}

public enum AgentResponse: Codable {
    case name(NameResponse)
    case child(ChildResponse)
    case parent(ParentResponse)
    case path(PathResponse)
    case info(InfoResponse)
    case list(ListResponse)
    case setAttributes(SetAttributesResponse)
    case createDirectory(CreateDirectoryResponse)
    case move(MoveResponse)
    case removeFile(RemoveFileResponse)
    case removeDirectory(RemoveDirectoryResponse)
    case exists(ExistsResponse)
}

public struct NameResponse: Codable {
    let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ChildResponse: Codable {
    let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct ParentResponse: Codable {
    let itemId: String

    public init(itemId: String) {
        self.itemId = itemId
    }
}

public struct PathResponse: Codable {
    let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct InfoResponse: Codable {
    let fileInfo: FileInfo

    public init(fileInfo: FileInfo) {
        self.fileInfo = fileInfo
    }
}

public struct ListResponse: Codable {
    let fileInfos: [FileInfo]

    public init(fileInfos: [FileInfo]) {
        self.fileInfos = fileInfos
    }
}

public struct ExistsResponse: Codable {
    let exists: Bool

    public init(exists: Bool) {
        self.exists = exists
    }
}

public struct SetAttributesResponse: Codable {
    public init() {}
}

public struct CreateDirectoryResponse: Codable {
    public init() {}
}

public struct MoveResponse: Codable {
    public init() {}
}

public struct RemoveFileResponse: Codable {
    public init() {}
}

public struct RemoveDirectoryResponse: Codable {
    public init() {}
}

public enum AgentError: Codable, Error {
    case profileNotFound(UUID)
}

public enum AgentResultError: Codable, Error {
    case agent(AgentError)
    case ssh(SSHError)
    case sftp(SFTPError)
    case unknown(domain: String, code: Int, message: String)

    public init(from error: any Error) {
        switch error {
        case let error as AgentError:
            self = .agent(error)
        case let error as SSHError:
            self = .ssh(error)
        case let error as SFTPError:
            self = .sftp(error)
        default:
            let nsError = error as NSError
            self = .unknown(
                domain: nsError.domain,
                code: nsError.code,
                message: nsError.localizedDescription
            )
        }
    }

    public var underlyingError: any Error {
        switch self {
        case .agent(let error): error
        case .ssh(let error): error
        case .sftp(let error): error
        case .unknown(let domain, let code, let message):
            NSError(
                domain: domain,
                code: code,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}

public enum AgentResult: Codable {
    case success(AgentResponse)
    case failure(AgentResultError)

    public func get() throws -> AgentResponse {
        switch self {
        case .success(let response): return response
        case .failure(let error): throw error.underlyingError
        }
    }
}
