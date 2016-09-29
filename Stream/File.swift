//===--- File.swift ----------------------------------------------===//
//Copyright (c) 2016 Crossroad Labs s.r.o.
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//http://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
//===----------------------------------------------------------------------===//

import Foundation

import Boilerplate
import ExecutionContext
import Future

public enum FileError : Error {
    case invalid(name: String)
}

public protocol FileSpi : ExecutionContextTenantProtocol {
    static func open(context:ExecutionContextProtocol, path:String, mode:File.Mode) -> Future<FileSpi>
    
    func readStream() -> RawReadable
}

public extension FileSpi {
    public static func open(context:ExecutionContextProtocol, path:String) -> Future<FileSpi> {
        return open(context: ExecutionContext.current, path: path, mode: .readonly)
    }
    
    public static func open(path:String, mode:File.Mode) -> Future<FileSpi> {
        return open(context: ExecutionContext.current, path: path, mode: mode)
    }
    
    public static func open(path:String) -> Future<FileSpi> {
        return open(context: ExecutionContext.current, path: path, mode: .readonly)
    }
}

internal extension ExecutionContextProtocol {
    var fileSpi:FileSpi.Type {
        get {
            switch self {
            case _ as DispatchExecutionContext:
                return DispatchFileSpi.self
            default:
                fatalError("Not supported context")
            }
        }
    }
}

public final class File {
    public struct Mode : OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        
        public static let readonly = Mode(rawValue: UInt(O_RDONLY))
        public static let writeonly = Mode(rawValue: UInt(O_WRONLY))
        public static let readwrite = Mode(rawValue: UInt(O_RDWR))
        
        public static let append = Mode(rawValue: UInt(O_APPEND))
        public static let create = Mode(rawValue: UInt(O_CREAT))
    }
    
    fileprivate let _spi:FileSpi
    
    private init(spi:FileSpi) {
        self._spi = spi
    }
    
    public static func open(context: ExecutionContextProtocol = ExecutionContext.current, path:String, mode:File.Mode = .readonly) -> Future<File> {
        let Spi = context.fileSpi
        let spi = Spi.open(context: context, path: path, mode: mode)
        return spi.map { spi in
            File(spi: spi)
        }
    }
}

public extension File {
    public func readStream() -> RawReadable {
        return self._spi.readStream()
    }
}
