//===--- WritableEvents.swift ----------------------------------------------===//
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

public protocol WritableEventEmitterProtocol : StreamEventEmitterProtocol {
    associatedtype OutChunk
}

public enum WritableSignalEvent : Event {
    public typealias Payload = Void
    case drain
    case finish
}

//TODO: think if there is a chance to make this generic with a real reader
public enum WritablePipeEvent: Event {
    public typealias Payload = Any
    case pipe
    case unpipe
}

public struct WritableEventGroup<E : Event> {
    internal let event:E
    
    private init(_ event:E) {
        self.event = event
    }
    
    public static var drain:WritableEventGroup<WritableSignalEvent> {
        return WritableEventGroup<WritableSignalEvent>(.drain)
    }
    
    public static var finish:WritableEventGroup<WritableSignalEvent> {
        return WritableEventGroup<WritableSignalEvent>(.finish)
    }
    
    public static var pipe:WritableEventGroup<WritablePipeEvent> {
        return WritableEventGroup<WritablePipeEvent>(.pipe)
    }
    
    public static var unpipe:WritableEventGroup<WritablePipeEvent> {
        return WritableEventGroup<WritablePipeEvent>(.unpipe)
    }
}

public extension WritableEventEmitterProtocol {
    public func on<E : Event>(_ groupedEvent: WritableEventGroup<E>) -> EventConveyor<E.Payload> {
        return self.on(groupedEvent.event)
    }
    
    public func once<E : Event>(_ groupedEvent: WritableEventGroup<E>, failOnError:@escaping (Error)->Bool = {_ in true}) -> Future<E.Payload> {
        return self.once(groupedEvent.event, failOnError: failOnError)
    }
    
    public func emit<E : Event>(_ groupedEvent: WritableEventGroup<E>, payload:E.Payload) {
        self.emit(groupedEvent.event, payload: payload)
    }
}
