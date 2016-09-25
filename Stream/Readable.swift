//===--- Readable.swift ----------------------------------------------===//
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

import Boilerplate
import Result
import ExecutionContext
import Event
import Future

public typealias ChunkProtocol = Creatable & BufferProtocol

public protocol ReadableSpiProtocol {
    associatedtype Element
    associatedtype Chunk : ChunkProtocol
    
    func _init(push:@escaping (Chunk?)->Bool)
    func _read(size:Int)
}

public class ReadableImpl<Spi: ReadableSpiProtocol> : ReadableEventEmitterProtocol {
    public typealias InChunk = Spi.Chunk
    
    private let _spi:Spi
    private let _highWatermark:Int
    fileprivate var _pipes:[(writable:AnyObject, off:Off)] = []
    
    public let dispatcher: EventDispatcher
    public let context: ExecutionContextProtocol
    
    public init(spi:Spi, dispatcher:EventDispatcher, context:ExecutionContextProtocol, highWatermark:Int? = nil/*16 KB*/) {
        self._spi = spi
        self._highWatermark = highWatermark ?? 1024*16/MemoryLayout<Spi.Chunk>.size
        self.dispatcher = dispatcher
        self.context = context
        context.execute {
            spi._init(push: self.push)
            spi._read(size: self._highWatermark)
        }
    }
    
    private var _buffers:[InChunk] = []
    private var _buffersSize:Int {
        get {
            var i = 0
            for b in _buffers {
                i += b.length
            }
            return i
        }
    }
    
    fileprivate var _flow:Off?
    
    private func push(chunk:InChunk?)->Bool {
        guard let chunk = chunk else {
            self.emit(.end, payload: ())
            return true
        }
        
        _buffers.append(chunk)
        self.emit(.readable, payload: ())
        
        return _buffersSize < _highWatermark
    }
    
    internal func read(size:Int?) -> InChunk? {
        return context.sync {
            defer {
                //request new portion of data on low buffers
                let size = self._highWatermark - self._buffersSize
                if size > 0 {
                    self.requestRead(size: size)
                }
            }
            
            guard let size = size else {
                var result = InChunk()
                
                for var buffer in self._buffers {
                    buffer.drainTo(buffer: &result)
                }
                
                self._buffers.removeAll(keepingCapacity: true)
                
                return result
            }
            
            if size > self._buffersSize {
                return nil
            }
            
            var left = size
            var result = InChunk()
            
            while left > 0 {
                let headSize = self._buffers.first!.length
                
                self._buffers[0].drainTo(buffer: &result, count: left)
                
                if self._buffers[0].length == 0 {
                    self._buffers.removeFirst()
                }
                
                left -= headSize
            }
            
            return result
        }
    }
    
    internal func requestRead(size:Int) {
        _spi._read(size: size)
    }
}

public protocol Readable : ReadableEventEmitterProtocol, AnyObject {
    associatedtype ReadableSpi : ReadableSpiProtocol
    associatedtype InElement = ReadableSpi.Element
    associatedtype InChunk  : ChunkProtocol = ReadableSpi.Chunk
    
    var _rimpl:ReadableImpl<ReadableSpi> {get}
    
    var defaultSize:Int {get}
}

public extension Readable {
    public func read(size:Int? = nil) -> InChunk? {
        //as is bullshit but swift is stupid
        let result = self._rimpl.read(size: size) as! InChunk?
        
        if let chunk = result, chunk.length > 0 {
            self.emit(.data, payload: chunk)
        }
        
        return result
    }
}

public extension Readable {
    public var paused:Bool {
        get {
            return self.context.sync {
                 nil == self._rimpl._flow
            }
        }
        set {
            self.context.execute {
                if newValue && self._rimpl._flow == nil {
                    self._rimpl._flow = self.on(.readable).react {
                        self.read()
                    }
                } else if !newValue && self._rimpl._flow != nil {
                    self._rimpl._flow?()
                    self._rimpl._flow = nil
                }
            }
        }
    }
    
    public func pause() -> Self {
        self.paused = true
        return self
    }
    
    public func resume() -> Self {
        self.paused = false
        return self
    }
}

public extension Readable {
    public var defaultSize:Int {
        get {
            return 1024
        }
    }
}

public extension Readable {
    public func pipe<W : Writable>(writable:W, end:Bool = true) -> W
        where W.WritableSpi.Element == InElement, W.WritableSpi.Chunk == InChunk {
        let off = writable._wimpl._pipe(r: self, end: end)
        
        self.context.execute {
            self._rimpl._pipes.append((writable: writable, off: off))
        }
        
        return writable
    }
    
    public func unpipe<W : Writable>(writable:W? = nil)
        where W.WritableSpi.Element == InElement, W.WritableSpi.Chunk == InChunk {
        self.context.execute {
            if let writable = writable {
                let pipeIndex = self._rimpl._pipes.index { e in
                    e.writable === writable
                }
                if let pipe = pipeIndex.map({self._rimpl._pipes[$0]}) {
                    pipe.off()
                    self._rimpl._pipes.remove(at: pipeIndex!)
                }
            } else {
                for pipe in self._rimpl._pipes {
                    pipe.off()
                }
                self._rimpl._pipes.removeAll()
            }
        }
    }
}

public extension Readable where InChunk : Creatable & BufferProtocol {
    public func drain() -> Future<InChunk> {
        let promise = Promise<InChunk>()
        
        var buffer = InChunk()
        
        let dataOff = self.on(.data).react { chunk in
            print(chunk.length)
            buffer.write(buffer: chunk)
        }
        
        let endOff = self.on(.end).react {
            try! promise.success(value: buffer)
        }
        
        let readableOff = self.on(.readable).react {
            //if we are not paused this one whould be called automatically
            if self.paused {
                self.read()
            }
        }
        
        let errorOff = self.on(.error).react { e in
            try! promise.fail(error: e)
        }
        
        promise.future.onComplete { (_:Result<InChunk,AnyError>) in
            dataOff()
            endOff()
            errorOff()
            readableOff()
        }
        
        return promise.future
    }
}

public class ReadableSpiBase<E, C : ChunkProtocol> : ReadableSpiProtocol {
    public typealias Element = E
    public typealias Chunk = C
    
    private (set) public var _push:(Chunk?)->Bool = {_ in false}
    
    public func _init(push:@escaping (Chunk?)->Bool) {
        _push = push
    }
    
    public func _read(size:Int) {
        print("You need to implement ReadableSpi::_read method")
    }
}

public class RawReadableSpi : ReadableSpiBase<UInt8, [UInt8]> {
}

public class StringReadableSpi : ReadableSpiBase<String, String> {
}

public protocol RawReadable : Readable {
    associatedtype ReadableSpi : RawReadableSpi
}

public protocol StringReadable : Readable {
    associatedtype ReadableSpi : StringReadableSpi
}

public class RawReadableSpiTest : RawReadableSpi {
    var data:[UInt8]? = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    
    /*public override func _init(push:(Chunk?)->Bool) {
        super._init(push)
    }*/
    
    public override func _read(size:Int) {
        ExecutionContext.main.execute {
            while let element = self.data?.first {
                self.data?.removeFirst()
                
                if(!self._push([element])) {
                    break
                }
            }
            
            if self.data?.isEmpty ?? false {
                self._push(nil)
                self.data = nil
            }
        }
    }
}

func f() {
    let aa = RawReadableSpi()
}

public class RawReadableTest: RawReadable {
    public typealias ReadableSpi = RawReadableSpiTest
    
    public let _rimpl: ReadableImpl<RawReadableSpiTest>
    public let dispatcher:EventDispatcher = EventDispatcher()
    public let context: ExecutionContextProtocol = ExecutionContext.main
    
    public init() {
        self._rimpl = ReadableImpl(spi: RawReadableSpiTest(), dispatcher: dispatcher, context: context, highWatermark: 2)
    }
}

/*class RawReadableTest : RawReadable {
    typealias ReadableSpi = RawReadableSpi
    let _impl:ReadableImpl<RawReadableSpi> = ReadableImpl<RawReadableSpi>(spi: RawReadableSpi())
    let dispatcher:EventDispatcher = EventDispatcher()
    let context: ExecutionContextType = ExecutionContext.current
    
    var paused: Bool = false
    
    func read(size:Int) -> [UInt8] {
        return []
    }
}*/

import Foundation

/*protocol Test {
    associatedtype A : ErrorProtocol
    
    var ttt:Self {get}
}

class T1: Test {
    typealias A = CommonRuntimeError
    
    let ttt:Test = T1()
}*/

func ff() {
    let rrt = RawReadableTest()
    
    let _ = rrt.on(.data).react { bytes in
        
    }
    
    let _ = rrt.on(.end).react {
        
    }
    
    let _ = rrt.on(.close).react {
        
    }
    
    rrt.drain().flatMap { buff in
        String(bytes: buff, encoding: String.Encoding.utf8)
    }.onSuccess { string in
        print(string)
    }
}
