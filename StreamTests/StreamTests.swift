//
//  StreamTests.swift
//  StreamTests
//
//  Created by Daniel Leping on 06/05/2016.
//  Copyright © 2016 Crossroad Labs s.r.o. All rights reserved.
//

import XCTest

import ExecutionContext
import Future
@testable import Stream

class StreamTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        //f123()
        
        //let test = RawReadableTest()
        File.open(path: "/etc/passwd", mode: .readonly).flatMap { passwd in
            passwd.readStream().drain()
        }.flatMap { data in
            String(bytes: data, encoding: .utf8)
        }.onSuccess { strdata in
            print(strdata)
        }
        
        /*future(context: main) {
            File.open (path: "/etc/passwd", mode: .readonly).readStream()
            }.flatMap { passwd in
                passwd.drain()
            }.flatMap { data in
                String(bytes: data, encoding: .utf8)
            }.onSuccess { strdata in
                print(strdata)
        }*/
        let w = RawWritableTest()
        /*File.createReadStream(filename: "/etc/passwd").onSuccess { s in
            s.pipe(writable: w)
        }*/
        
        //test.pipe(writable: w)
        
        
        let expectation = self.expectation(description: "some")
        /*test.drain().onSuccess { result in
            print(result)
            XCTAssertEqual(result, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
            //expectation.fulfill()
        }*/
        
        self.waitForExpectations(timeout: 20000, handler: nil)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
