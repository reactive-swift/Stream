//===--- Dispatch.swift ----------------------------------------------===//
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

internal class DispatchFileSpi : FileSpi {
    let context: ExecutionContextProtocol
    let fd: Int32
    
    init(context:ExecutionContextProtocol, fd:Int32) {
        self.context = context
        self.fd = fd
    }
    
    public static func open(context:ExecutionContextProtocol, path:String, mode:File.Mode) -> Future<FileSpi> {
        let fdo = path.data(using: .utf8)?.withUnsafeBytes { bytes in
            Darwin.open(bytes, Int32(mode.rawValue) | O_NONBLOCK)
        }
        
        return fdo.map { fd in
            Future(value: DispatchFileSpi(context: context, fd: fd))
        }.getOr {
            Future(error: FileError.invalid(name: path))
        }
    }
    
    public func readStream() -> RawReadable {
        //TODO: request actual queue from the context
        //first of all need to add it in ExecutionContext
        let queue = DispatchQueue.main
        let dio = DispatchIO(type: .stream, fileDescriptor: fd, queue: queue, cleanupHandler: {_ in})
        return RawReadable(context: self.context, spi: DispatchReadableSpi(io: dio, queue: queue))
    }
}

//TODO: move to boilerplate
extension Optional {
    func filter(_ f: (Wrapped) -> Bool) -> Optional {
        return flatMap { wrapped in
            if !f(wrapped) {
                return .none
            }
            return wrapped
        }
    }
    
    func filterNot(_ f: (Wrapped) -> Bool) -> Optional {
        return filter {!f($0)}
    }
}

public class DispatchReadableSpi : RawReadableSpi {
    private let _dio:DispatchIO
    private let _queue:DispatchQueue
    
    internal init(io:DispatchIO, queue:DispatchQueue) {
        _dio = io
        _queue = queue
        super.init()
    }
    
    private var reading = false
    
    public override func _read(size:Int) {
        if reading {
            return
        }
        
        reading = true
        
        _dio.read(offset: 0, length: size, queue: _queue) { (done, data, error) in
            if done {
                self.reading = false
            }
            
            if CError.isError(error) {
                //TODO: a way to report error
            }
            
            //we anyways don't serve more than one request, so let it continue here
            let _ = self._push(data.filterNot{$0.isEmpty}.map({Array($0)}))
        }
    }
}
