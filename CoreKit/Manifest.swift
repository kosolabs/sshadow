import Common
import Foundation
import SwiftLibSSH

struct Manifest: Message {
    struct Entry: Message {
        enum Kind: Message {
            case folder
            case file(size: UInt64)
            case symlink(target: String)
        }

        let path: String
        let kind: Kind
        let mode: mode_t

        init(path: String, kind: Kind, mode: mode_t) {
            self.path = path
            self.kind = kind
            self.mode = mode
        }

        init(path: String, kind: Kind) {
            self.path = path
            self.kind = kind
            switch kind {
            case .folder:
                self.mode = Item.Flags.all.mode
            default:
                self.mode = Item.Flags.rw.mode
            }
        }

        func path(under root: String) -> String {
            path.isEmpty ? root : root + "/" + path
        }

        func url(under root: URL) -> URL {
            path.isEmpty ? root : root.appending(path: path)
        }

        func child(named name: String) -> String {
            path.isEmpty ? name : path + "/" + name
        }
    }

    let entries: [Entry]

    var root: Entry { entries[0] }

    init(entries: [Entry]) throws {
        guard entries.first?.path == "",
            entries.allSatisfy({
                $0.kind != .folder || $0.mode & 0o300 == 0o300
            })
        else {
            throw CoreError.cannotSynchronize
        }
        self.entries = entries
    }

    init(from root: URL) throws {
        let fm = FileManager.default
        let rootAttrs = try fm.attributesOfItem(
            atPath: root.path(percentEncoded: false)
        )
        switch rootAttrs[.type] as? FileAttributeType {
        case .typeDirectory:
            break
        case .typeRegular:
            let kind = Entry.Kind.file(size: (rootAttrs[.size] as? UInt64) ?? 0)
            try self.init(entries: [Entry(path: "", kind: kind)])
            return
        default:
            throw CoreError.cannotSynchronize
        }

        var entries = [Entry(path: "", kind: .folder)]
        var pending = [entries[0]]
        while !pending.isEmpty {
            let folder = pending.removeFirst()
            let names = try fm.contentsOfDirectory(
                atPath: folder.url(under: root).path(percentEncoded: false)
            )
            for name in names.sorted() {
                let relative = folder.child(named: name)
                let path = root.appending(path: relative)
                    .path(percentEncoded: false)
                let attrs = try fm.attributesOfItem(atPath: path)
                let kind: Entry.Kind
                switch attrs[.type] as? FileAttributeType {
                case .typeDirectory:
                    kind = .folder
                case .typeRegular:
                    kind = .file(size: (attrs[.size] as? UInt64) ?? 0)
                case .typeSymbolicLink:
                    kind = .symlink(
                        target: try fm.destinationOfSymbolicLink(atPath: path)
                    )
                default:
                    throw CoreError.cannotSynchronize
                }
                let entry = Entry(
                    path: relative,
                    kind: kind,
                    mode: mode(attrs[.posixPermissions] as? Int)
                )
                entries.append(entry)
                if kind == .folder { pending.append(entry) }
            }
        }

        try self.init(entries: entries)
    }

    init(from root: String, sftp: SFTPClient) async throws {
        let rootAttrs = try await sftp.attributes(
            at: root,
            followSymlinks: false
        )
        guard rootAttrs.type == .directory else {
            throw CoreError.cannotSynchronize
        }

        var entries = [Entry(path: "", kind: .folder)]
        var pending = [entries[0]]
        while !pending.isEmpty {
            let folder = pending.removeFirst()
            let children = try await sftp.withDirectory(
                at: folder.path(under: root)
            ) { dir in
                var children: [SFTPAttributes] = []
                for try await attrs in dir { children.append(attrs) }
                return children
            }
            let named = children.compactMap { attrs in
                attrs.name.map { ($0, attrs) }
            }
            for (name, attrs) in named.sorted(by: { $0.0 < $1.0 }) {
                let relative = folder.child(named: name)
                let kind: Entry.Kind
                switch attrs.type {
                case .directory:
                    kind = .folder
                case .regular:
                    kind = .file(size: attrs.size ?? 0)
                case .symlink:
                    kind = .symlink(
                        target: try await sftp.symlinkTarget(
                            at: root + "/" + relative
                        )
                    )
                default:
                    throw CoreError.cannotSynchronize
                }
                let entry = Entry(
                    path: relative,
                    kind: kind,
                    mode: mode(attrs.permissions)
                )
                entries.append(entry)
                if kind == .folder { pending.append(entry) }
            }
        }

        try self.init(entries: entries)
    }

    func totalSize() -> UInt64 {
        entries.reduce(0) { total, entry in
            if case .file(let size) = entry.kind { total + size } else { total }
        }
    }
}

private func mode<T: BinaryInteger>(_ permissions: T?) -> mode_t {
    mode_t(truncatingIfNeeded: permissions ?? 0) & 0o7777
}
