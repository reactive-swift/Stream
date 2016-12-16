//===--- ReadableEvents.swift ----------------------------------------------===//
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

import Event
import Future

public protocol ReadableEventEmitterProtocol : StreamEventEmitterProtocol {
    associatedtype InChunk
}

public enum ReadableDataEvent<Chunk> : Event {
    public typealias Payload = Chunk
    case event
}

public enum ReadableSignalEvent : Event {
    public typealias Payload = Void
    case end
    case readable
}

public struct ReadableEventGroup<E : Event, Payload> {
    internal let event:E
    
    private init(_ event:E) {
        self.event = event
    }
    
    public static var data:ReadableEventGroup<ReadableDataEvent<Payload>, Payload> {
        return ReadableEventGroup<ReadableDataEvent<Payload>, Payload>(.event)
    }
    
    public static var end:ReadableEventGroup<ReadableSignalEvent, Payload> {
        return ReadableEventGroup<ReadableSignalEvent, Payload>(.end)
    }
    
    public static var readable:ReadableEventGroup<ReadableSignalEvent, Payload> {
        return ReadableEventGroup<ReadableSignalEvent, Payload>(.readable)
    }
}

public extension ReadableEventEmitterProtocol {
    public func on<E : Event>(_ groupedEvent: ReadableEventGroup<E, InChunk>) -> SignalStream<E.Payload> {
        return self.on(groupedEvent.event)
    }
    
    public func once<E : Event>(_ groupedEvent: ReadableEventGroup<E, InChunk>, failOnError:@escaping (Error)->Bool = {_ in true}) -> Future<E.Payload> {
        return self.once(groupedEvent.event, failOnError: failOnError)
    }
    
    public func emit<E : Event>(_ groupedEvent: ReadableEventGroup<E, InChunk>, payload:E.Payload) {
        self.emit(groupedEvent.event, payload: payload)
    }
}
