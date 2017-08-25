//
//  HashChain.swift
//  Kryptonite
//
//  Created by Alex Grinman on 7/29/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import JSON

class HashChain {
    
    /// A request to the HashChain service
    struct Request:JsonWritable {
        let publicKey:Data
        let payload:String
        let signature:Data
        
        var object: Object {
            return ["public_key": publicKey.toBase64(),
                    "payload": payload,
                    "signature": signature.toBase64()]
        }
        
    }
    
    /// Hash chain errors
    enum Errors:Error {
        case badSignature
        case badPayload
        case badOperation
        case badBlockHash
        
        case missingCreateChain
        case unexpectedBlock

        case teamPublicKeyMismatch
    }

    /// A response from the HashChain service
    struct Response:JsonReadable {
        let blocks:[Block]
        let hasMore:Bool
                
        init(blocks:[Block], hasMore:Bool) {
            self.blocks = blocks
            self.hasMore = hasMore
        }
        
        init(json: Object) throws {
            try self.init(blocks: [Block](json: json ~> "blocks"),
                          hasMore: json ~> "more")
        }
        
    }

    /// A payload and it's signature
    struct Block:JsonReadable {
        let payload:String
        let signature:Data
        
        init(payload:String, signature:Data) {
            self.payload = payload
            self.signature = signature
        }
        init(json: Object) throws {
            try self.init(payload: json ~> "payload",
                          signature: ((json ~> "signature") as String).fromBase64())
        }
        
        func hash() -> Data {
            return Data(bytes: [UInt8](payload.utf8)).SHA256
        }
    }
    
    struct VerifiedBlock {
        let payload:Payload
        let signature:Data
    }

    /// The types of request payloads
    enum Payload:Jsonable {
        case create(CreateChain)
        case read(ReadBlock)
        case append(AppendBlock)
        
        init(json: Object) throws {
            
            if let create:Object = try? json ~> "create_chain" {
                self = try .create(CreateChain(json: create))
            }
            else if let read:Object = try? json ~> "read_block" {
                self = try .read(ReadBlock(json: read))
            }
            else if let append:Object = try? json ~> "append_block" {
                self = try .append(AppendBlock(json: append))
            }
            else {
                throw Errors.badPayload
            }
        }
        
        var object: Object {
            switch self {
            case .create(let create):
                return ["create_chain": create.object]
            case .read(let read):
                return ["read_block": read.object]
            case .append(let append):
                return ["append_block": append.object]
            }
        }
    }
    
    
    struct CreateChain:Jsonable {
        let teamPublicKey:Data
        let teamInfo:Team.Info
        
        init(teamPublicKey:Data, teamInfo:Team.Info) {
            self.teamPublicKey = teamPublicKey
            self.teamInfo = teamInfo
        }
        
        init(json: Object) throws {
            try self.init(teamPublicKey: ((json ~> "team_public_key") as String).fromBase64(),
                          teamInfo: Team.Info(json: json ~> "team_info"))
        }
        
        var object: Object {
            return ["team_public_key": teamPublicKey.toBase64(),
                    "team_info": teamInfo.object]
        }
    }
    
    struct ReadBlock:Jsonable {
        let teamPublicKey:Data
        let nonce:Data
        let unixSeconds:UInt64
        let lastBlockHash:Data?
        
        init(teamPublicKey:Data, nonce:Data, unixSeconds:UInt64, lastBlockHash:Data? = nil) {
            self.teamPublicKey = teamPublicKey
            self.nonce = nonce
            self.unixSeconds = unixSeconds
            self.lastBlockHash = lastBlockHash
        }
        
        init(json: Object) throws {
            
            var lastBlockHashData:Data?
            if let lastBlockHash:String = try? json ~> "last_block_hash" {
                lastBlockHashData = try lastBlockHash.fromBase64()
            }
            
            try self.init(teamPublicKey: ((json ~> "team_public_key") as String).fromBase64(),
                          nonce: ((json ~> "nonce") as String).fromBase64(),
                          unixSeconds: json ~> "unix_seconds",
                          lastBlockHash: lastBlockHashData)
        }
        
        var object: Object {
            var map:Object = ["team_public_key": teamPublicKey.toBase64(),
                              "nonce": nonce.toBase64(),
                              "unix_seconds": unixSeconds]
            
            if let lastBlockHash = lastBlockHash {
                map["last_block_hash"] = lastBlockHash.toBase64()
            }
            
            return map
        }
    }
    
    struct AppendBlock:Jsonable {
        let lastBlockHash:Data
        let operation:Operation
        
        init(lastBlockHash:Data, operation:Operation) {
            self.lastBlockHash = lastBlockHash
            self.operation = operation
        }
        
        init(json: Object) throws {
            try self.init(lastBlockHash: ((json ~> "last_block_hash") as String).fromBase64(),
                          operation: try Operation(json: json ~> "operation"))
        }
        
        var object: Object {
            return ["last_block_hash": lastBlockHash.toBase64(),
                    "operation": operation.object]
        }
    }
    
    
    /// Types of HashChain operations
    enum Operation:Jsonable {
        case inviteMember(MemberInvitation)
        case cancelInvite(MemberInvitation)
        
        //  signed with nonce_key_pair
        //  only block type written by non-admin
        //  new member first reads blockchain signing with nonce_key_pair, then appends AcceptInvite block
        case acceptInvite(Team.MemberIdentity)
        
        case addMember(Team.MemberIdentity)
        case removeMember(SodiumPublicKey)
        
        case setPolicy(Team.PolicySettings)
        case setTeamInfo(Team.Info)
        
        case pinHostKey(SSHHostKey)
        case unpinHostKey(SSHHostKey)
        
        init(json: Object) throws {
            if let invite:Object = try? json ~> "invite_member" {
                self = try .inviteMember(MemberInvitation(json: invite))
            }
            else if let cancel:Object = try? json ~> "cancel_invite" {
                self = try .cancelInvite(MemberInvitation(json: cancel))
            }
            else if let accept:Object = try? json ~> "accept_invite" {
                self = try .acceptInvite(Team.MemberIdentity(json: accept))
            }
            else if let add:Object = try? json ~> "add_member" {
                self = try .addMember(Team.MemberIdentity(json: add))
            }
            else if let remove:String = try? json ~> "remove_member" {
                self = try .removeMember(remove.fromBase64())
            }
            else if let policy:Object = try? json ~> "set_policy" {
                self = try .setPolicy(Team.PolicySettings(json: policy))
            }
            else if let info:Object = try? json ~> "set_team_info" {
                self = try .setTeamInfo(Team.Info(json: info))
            }
            else if let host:Object = try? json ~> "pin_host_key" {
                self = try .pinHostKey(SSHHostKey(json: host))
            }
            else if let host:Object = try? json ~> "unpin_host_key" {
                self = try .unpinHostKey(SSHHostKey(json: host))
            }
            else {
                throw Errors.badOperation
            }
        }
        
        var object: Object {
            switch self {
            case .inviteMember(let invite):
                return ["invite_member": invite.object]
            case .cancelInvite(let cancel):
                return ["cancel_invite": cancel.object]
            case .acceptInvite(let accept):
                return ["accept_invite": accept.object]
            case .addMember(let add):
                return ["add_member": add.object]
            case .removeMember(let remove):
                return ["remove_member": remove.toBase64()]
            case .setPolicy(let policy):
                return ["set_policy": policy.object]
            case .setTeamInfo(let info):
                return ["set_team_info": info.object]
            case .pinHostKey(let host):
                return ["pin_host_key": host.object]
            case .unpinHostKey(let host):
                return ["unpin_host_key": host.object]
            }
        }
    }
    
    /// Data Structures
    struct MemberInvitation:Jsonable {
        let noncePublicKey:Data
        
        init(json: Object) throws {
            noncePublicKey = try ((json ~> "nonce_public_key") as String).fromBase64()
        }
        
        var object: Object {
            return ["nonce_public_key": noncePublicKey.toBase64()]
        }
    }
}