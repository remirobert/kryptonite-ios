//
//  KeychainStorage.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/1/16.
//  Copyright © 2016 KryptCo, Inc. All rights reserved.
//

import Foundation

private let KrKeychainServiceName = "kr_keychain_service"

enum KeychainStorageError:Error {
    case notFound
    case saveError(OSStatus?)
    case delete(OSStatus?)
    case unknown(OSStatus?)
}

class KeychainStorage {
    
    var service:String
    var mutex = Mutex()
    
    init(service:String = KrKeychainServiceName) {
        self.service = service
    }
    
    func setData(key:String, data:Data) throws {
        mutex.lock()
        defer { self.mutex.unlock() }
        
        let params: [String : Any] = [String(kSecClass): kSecClassGenericPassword,
                      String(kSecAttrService): service,
                      String(kSecAttrAccount): key,
                      String(kSecValueData): data,
                      String(kSecAttrAccessible): KeychainAccessiblity]
        
        let _ = SecItemDelete(params as CFDictionary)
        
        let status = SecItemAdd(params as CFDictionary, nil)
        guard status.isSuccess() else {
            throw KeychainStorageError.saveError(status)
        }
        
    }

    
    func set(key:String, value:String) throws {
        try setData(key: key, data: value.utf8Data())
    }
    
    func getData(key:String) throws -> Data {
        mutex.lock()
        defer { self.mutex.unlock() }

        let params:[String : Any] = [String(kSecClass): kSecClassGenericPassword,
                      String(kSecAttrService): service,
                      String(kSecAttrAccount): key,
                      String(kSecReturnData): kCFBooleanTrue,
                      String(kSecMatchLimit): kSecMatchLimitOne,
                      String(kSecAttrAccessible): KeychainAccessiblity]
        
        var object:AnyObject?
        let status = SecItemCopyMatching(params as CFDictionary, &object)
        
        if status == errSecItemNotFound {
            throw KeychainStorageError.notFound
        }
        
        guard let data = object as? Data, status.isSuccess() else {
            throw KeychainStorageError.unknown(status)
        }
        
        return data
    }
    
    func get(key:String) throws -> String {
        return try self.getData(key: key).utf8String()
    }

    
    func delete(key:String) throws {
        mutex.lock()
        defer { self.mutex.unlock() }

        let params: [String : Any] = [String(kSecClass): kSecClassGenericPassword,
                      String(kSecAttrService): service,
                      String(kSecAttrAccount): key]
        
        let status = SecItemDelete(params as CFDictionary)
        
        guard status.isSuccess() else {
            throw KeychainStorageError.delete(status)
        }
    }
    
}
