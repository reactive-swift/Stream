//===--- Buffer.swift ----------------------------------------------===//
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

//TODO: move creatable to boilerplate
public protocol Creatable {
    init()
}

extension Array : Creatable {
}

extension String : Creatable {
}

public protocol BufferProtocol {
    associatedtype Element
    
    var elements:[Element] {get}
    var length:Int {get}
    
    mutating func write(elements:[Element])
    mutating func write(element:Element)
    
    mutating func drainTo<Buffer : BufferProtocol>(buffer:inout Buffer, count:Int?) where Buffer.Element == Element
}

public extension BufferProtocol {
    public mutating func drainTo<Buffer : BufferProtocol>(buffer:inout Buffer) where Buffer.Element == Element {
        self.drainTo(buffer: &buffer, count: nil)
    }
}

public extension BufferProtocol {
    public mutating func write<T : BufferProtocol>(buffer:T) where T.Element == Element {
        self.write(elements: buffer.elements)
    }
}

extension Array : BufferProtocol {
    public var elements:[Element] {
        get {
            return self
        }
    }
    
    public var length: Int {
        get {
            return self.count
        }
    }
    
    public mutating func write(elements:[Element]) {
        self.append(contentsOf: elements)
    }
    
    public mutating func write(element:Element) {
        self.append(element)
    }
    
    public mutating func drainTo<Buffer : BufferProtocol>(buffer:inout Buffer, count:Int?) where Buffer.Element == Element {
        if let count = count, count < length {
            let toWrite = self.prefix(count)
            buffer.write(elements: Array(toWrite))
            self.removeSubrange(0..<count)
        } else {
            buffer.write(buffer: self)
            self.removeAll(keepingCapacity: true)
        }
    }
}

extension String : BufferProtocol {
    public typealias Element = String
    
    public var elements:[Element] {
        get {
            return [self]
        }
    }
    
    public var length: Int {
        get {
            return self.utf8.count
        }
    }
    
    public mutating func write(elements:[Element]) {
        for string in elements {
            self.write(string)
        }
    }
    
    public mutating func write(element:Element) {
        self.append(element)
    }
    
    public mutating func drainTo<Buffer : BufferProtocol>(buffer:inout Buffer, count:Int?) where Buffer.Element == Element {
        if let count = count, count < length {
            let range = self.startIndex..<self.index(startIndex, offsetBy: count+1)
            let toWrite = self.substring(with: range)
            buffer.write(element: toWrite)
            self.removeSubrange(range)
        } else {
            buffer.write(buffer: self)
            self.removeAll(keepingCapacity: true)
        }
    }
}
