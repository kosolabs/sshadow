import Foundation

public enum CoreRequest: Message, PrettyDescribable {
    case currentAnchor(CurrentAnchorRequest)
    case limits(LimitsRequest)
    case ignoreFilenames(IgnoreFilenamesRequest)
    case name(NameRequest)
    case child(ChildRequest)
    case parent(ParentRequest)
    case item(ItemRequest)
    case list(ListRequest)
    case watch(WatchRequest)
    case unwatch(UnwatchRequest)
    case changes(ChangesRequest)
    case materializedItemsChanged(MaterializedItemsChangedRequest)
    case setAttributes(SetAttributesRequest)
    case createSymlink(CreateSymlinkRequest)
    case createDirectory(CreateDirectoryRequest)
    case move(MoveRequest)
    case removeFile(RemoveFileRequest)
    case removeDirectory(RemoveDirectoryRequest)

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> CoreRequest {
        try JSONDecoder().decode(CoreRequest.self, from: data)
    }
}

public enum CoreProgressRequest: Message, PrettyDescribable {
    case upload(UploadRequest)
    case download(DownloadRequest)
    case stream(StreamRequest)

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> CoreProgressRequest {
        try JSONDecoder().decode(CoreProgressRequest.self, from: data)
    }
}

public enum CoreResult<Response: Message>: Message, PrettyDescribable {
    case success(Response)
    case failure(CoreError)

    public func get() throws(CoreError) -> Response {
        switch self {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}
