//===--- Writable.swift ----------------------------------------------===//
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

import Result
import Boilerplate
import ExecutionContext
import Event
import Future

public protocol WritableSpiProtocol {
    associatedtype Element
    associatedtype Chunk : ChunkProtocol
    
    func _init()
    func _write(chunks:[Chunk]) -> Future<Void>
    func _close() -> Future<Void>
}

public class WritableImpl<Spi: WritableSpiProtocol> : WritableEventEmitterProtocol {
    public typealias OutChunk = Spi.Chunk
    private typealias PipeConnection = (readable:AnyObject, dataOff:SafeTask, errorOff:SafeTask, endOff:SafeTask?)
    
    private let _spi:Spi
    private var _buffers:[(chunk: OutChunk, promise:Promise<Void>)] = []
    private var _ops:Array<SafeTask> = []
    private var _pipe:PipeConnection? = nil {
        didSet {
            if let pipe = oldValue {
                pipe.dataOff()
                pipe.errorOff()
                pipe.endOff?()
                
                self.emit(.unpipe, payload: pipe.readable)
            }
        }
    }
    
    public let dispatcher: EventDispatcher
    public let context: ExecutionContextProtocol
    
    public init(spi:Spi, dispatcher:EventDispatcher, context:ExecutionContextProtocol) {
        self._spi = spi
        self.dispatcher = dispatcher
        self.context = context
    }
    
    private var _writing:Bool = false
    
    fileprivate var _corked:Bool = false {
        didSet {
            if _corked != oldValue && oldValue {
                _flush(chunks: _buffers)
                _buffers.removeAll()
            }
        }
    }
    
    fileprivate func _write(data:OutChunk) -> Future<Void> {
        let promise = Promise<Void>()
        
        if _corked {
            _buffers.append((chunk: data, promise: promise))
        } else {
            _flush(chunks: [(chunk: data, promise: promise)])
        }
        
        return promise.future
    }
    
    private func _flush(chunks:[(chunk: OutChunk, promise:Promise<Void>)]) {
        self.context.execute {
            self._ops.append {
                let data = chunks.map({$0.chunk})
                
                let writeResult = self._spi._write(chunks: data)
                
                for chunk in chunks {
                    chunk.promise.completeWith(future: writeResult)
                }
                
                writeResult.onSuccess {
                    let _ = self._ops.removeFirst()
                    
                    if let nextOp = self._ops.first {
                        nextOp()
                    } else {
                        self.emit(.drain, payload: ())
                    }
                }
                
                writeResult.onFailure { e in
                    self._error(e: e)
                }
            }
            
            if self._ops.count == 1 {
                self._ops.first?()
            }
        }
    }
    
    fileprivate func _end() -> Future<Void> {
        return self._spi._close()
    }
    
    fileprivate func _error(e:Error) {
        self._buffers.removeAll()
        self._ops.removeAll()
        self.emit(.error, payload: e)
    }
    
    internal func _pipe<R : ReadableEventEmitterProtocol>(r:R, end:Bool) -> Off where Spi.Chunk == R.InChunk {
        context.execute {
            self._pipe = nil
            
            let dataOff = r.on(.data).settle(in: self.context).react { chunk in
                //maybe we should handle the future result??
                let _ = self._write(data: chunk)
            }
            
            let errorOff = r.on(.error).settle(in: self.context).react { e in
                self.emit(.error, payload: e)
                self.context.execute {
                    self._pipe = nil
                }
            }
            
            let endOff:SafeTask? = !end ? nil : r.on(.end).settle(in: self.context).react {
                let _ = self._end()
            }
            
            self._pipe = PipeConnection(readable: r, dataOff: dataOff, errorOff:errorOff, endOff:endOff)
        }
        
        return {
            self.context.execute {
                self._pipe = nil
            }
        }
    }
    
    internal func _unpipe<R : Readable>(readable:R) where Spi.Element == R.InElement, Spi.Chunk == R.InChunk {
        context.execute {
            if self._pipe.map({$0.readable === readable}) ?? false {
                self._pipe = nil
            } else {
                readable.emit(.error, payload: StreamError.invalidUnpipe)
            }
        }
    }
}

public protocol Writable : WritableEventEmitterProtocol, AnyObject {
    associatedtype WritableSpi : WritableSpiProtocol
    
    associatedtype OutElement = WritableSpi.Element
    associatedtype OutChunk = WritableSpi.Chunk
    
    var _wimpl:WritableImpl<WritableSpi> {get}
}

public extension Writable {
    public func cork() {
        context.execute {
            self._wimpl._corked = true
        }
    }
    
    public func uncork() {
        context.execute {
            self._wimpl._corked = false
        }
    }
    
    //future is to be resolved once the data is flushed. Is resolved right away in case the data is written immediately
    public func write(data:OutChunk) -> Future<Void> {
        //freaking swift. I know the type is same here
        return _wimpl._write(data: data as! WritableImpl<WritableSpi>.OutChunk)
    }
    
    //future is to be resolved once all the data is flushed
    public func end(data:OutChunk? = nil) -> Future<Void> {
        let writeResult = data.map({self.write(data: $0)}) ?? Future<Void>(value: ())
        
        return writeResult.flatMap { (_)->Future<Void> in
            let end = self._wimpl._end()
            
            end.onSuccess {
                self.emit(.finish, payload: ())
            }
            
            end.onFailure { e in
                self._wimpl._error(e: e)
            }
            
            return end
        }
    }
}

public class WritableSpiBase<E, C : ChunkProtocol> : WritableSpiProtocol {
    public typealias Element = E
    public typealias Chunk = C
    
    public func _init() {
    }
    
    public func _write(chunks:[Chunk]) -> Future<Void> {
        CommonRuntimeError.NotImplemented(what: "ReadableSpi::_write(chunks:[Chunk])").panic()
    }
    
    public func _close() -> Future<Void> {
        CommonRuntimeError.NotImplemented(what: "ReadableSpi::_close()").panic()
    }
}

public class RawWritableSpi : WritableSpiBase<UInt8, [UInt8]> {
}

public class StringWritableSpi : WritableSpiBase<String, String> {
}

public protocol RawWritable : Writable {
    associatedtype WritableSpi : RawWritableSpi
}

public protocol StringWritable : Writable {
    associatedtype WritableSpi : StringWritableSpi
}

public class RawWritableSpiTest : RawWritableSpi {
    public override func _write(chunks:[Chunk]) -> Future<Void> {
        return future(context: main) {
            print("Chunks:", chunks)
        }
    }
    
    public override func _close() -> Future<Void> {
        return Future<Void>(value: ())
    }
}

public class RawWritableTest: RawWritable {
    public typealias WritableSpi = RawWritableSpiTest
    
    public let _wimpl: WritableImpl<RawWritableSpiTest>
    public let dispatcher:EventDispatcher = EventDispatcher()
    public let context: ExecutionContextProtocol = ExecutionContext.main
    
    public init() {
        self._wimpl = WritableImpl(spi: RawWritableSpiTest(), dispatcher: dispatcher, context: context)
    }
}
