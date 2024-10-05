// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import {IRegister} from "./interfaces/IRegister.sol";
import {Registry} from "./Registry.sol";
import {Base64} from "./libraries/Base64.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {IVerifierCSCA} from "./interfeces/IVerifierCSCA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@zk-kit/imt.sol/internal/InternalLeanIMT.sol";

/*** 
                                                                          ,--"""",--.__,---[],-------._                             
                                                                        ,"   __,'            \         \--""""""==;-                
                                                                      ," _,-"  "/---.___     \       ___\   ,-'',"                  
                                                                     /,-'      / ;. ,.--'-.__\  _,-"" ,| `,'   /                    
                                                                    /``""""-._/,-|:\       []\,' ```-/:;-. `. /                     
                                                                              `  ;:::      ||       /:,;  `-.\                      
                                                                                 =.,'__,---||-.____',.=                             
                                                                                 =(:\_     ||__    ):)=                             
                                                                                ,"::::`----||::`--':::"._                           
                                                                              ,':::::::::::||::::::::::::'.                         
                                                                     .__     ;:::.-.:::::__||___:::::.-.:::\     __,                
                                                                        """-;:::( O )::::>_|| _<::::( O )::::-"""                   
                                                                    =======;:::::`-`:::::::||':::::::`-`:::::\=======               
                                                                     ,--"";:::_____________||______________::::""----.          , , 
                                                                          ; ::`._(    |    |||     |   )_,'::::\_,,,,,,,,,,____/,'_,
                                                                        ,;    :::`--._|____[]|_____|_.-'::::::::::::::::::::::::);_ 
                                                                       ;/ /      :::::::::,||,:::::::::::::::::::::::::::::::::::/  
                                                                      /; ``''''----------/,'/,__,,,,,____:::::::::::::::::::::,"    
                                                                      ;/                :);/|_;| ,--.. . ```-.:::::::::::::_,"      
                                                                     /;                :::):__,'//""\\. ,--.. \:::,:::::_,"         
                                                                    ;/              :::::/ . . . . . . //""\\. \::":__,"            
                                                                    ;/          :::::::,' . . . . . . . . . . .:`::\                
   _      _      _      _      _      _      _      _      _      _ ';   _  :::::::__,'. ,--.._. .,--. . . ._. .:`::`               
 _( )_  _( )_  _( )_  _( )_  _( )_  _( )_  _( )_  _( )_  _( )_  _( )'; _(__,..--'''-._. //""\\.).//""\\_. ,--.. :`:::`              
(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o ;)(_ / _\\_.//""\\ . .)._.o._.(. . .)//""\\.(:`::`)             
 (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_;  (/,_)  (_._. .(.,.). ._._. .(.,.). ._._. .:`::`              
   _                                                                ;   (          . . . . . . . . . . . . . . . ;:::`              
 _( )_          ██╗ █████╗ ██████╗  █████╗ ███╗   ██╗    ███████╗██████╗;██╗████████╗██╗.██████╗.███╗ . ██╗ . . ;':::`              
(_ o _)         ██║██╔══██╗██╔══██╗██╔══██╗████╗  ██║    ██╔════╝██╔══██╗██║╚══██╔══╝██║██╔═══██╗████╗ .██║. . .;`:::_)             
 (_,_)          ██║███████║██████╔╝███████║██╔██╗ ██║    █████╗  ██║,:██║██║   ██║   ██║██║ . ██║██╔██╗ ██║ . . ;`::;`              
   _       ██   ██║██╔══██║██╔═══╝ ██╔══██║██║╚██╗██║    ██╔══╝  ██║ ,██║██║   ██║   ██║██║. .██║██║╚██╗██║. . ;':::;`              
 _( )_     ╚█████╔╝██║  ██║██║     ██║  ██║██║ ╚████║    ███████╗██████╔╝██║   ██║   ██║╚██████╔╝██║.╚████║ . ,':::;)_              
(_ o _)     ╚════╝ ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝    ╚══════╝╚═════╝ ╚═╝.  ╚═╝   ╚═╝ ╚═════╝ ╚═╝ .╚═══╝ .,':::;` _)             
 (_,_)                                                                  :    `.       . . . . . . . . . . . ;::::;`,_)              
   _      _      _      _      _      _      _      _      _      _      '.    `-.   . . . . ._. . . . . ,-'::::;  _                
 _( )_  _( )_  _( )_  _( )_  _( )_  _( )_  _( )_  _( )_  _( )_  _( )_  _( )`:__( )``--..___________..--'':::::;'`_( )_              
(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(_ o _)(`._::,.:,.:,:_ctr_:,:,.::,.:_;'`_)(_ o _)             
 (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,_)  (_,`"\/"\/\/'""""`\/"\/""\/"(_,_)  (_,_) 
 
 ***/

contract OpenPassportRegister is IRegister, Ownable {
    Registry public immutable registry;
    using Base64 for *;
    using Strings for uint256;

    using InternalLeanIMT for LeanIMTData;
    LeanIMTData internal imt;

    // poseidon("E-PASSPORT")
    bytes32 public attestationId =
        bytes32(
            0x12d57183e0a41615471a14e5a93c87b9db757118c1d7a6a9f73106819d656f24
        );

    mapping(uint256 => bool) public nullifiers;
    mapping(uint256 => bool) public merkleRootsCreated;
    mapping(uint256 => address) public verifiers;
    mapping(uint256 => address) public cscaVerifier;

    constructor(Registry r) {
        registry = r;
        transferOwnership(msg.sender);
    }

    function validateProof(
        RegisterProof calldata proof,
        CSCAProof calldata proof_csca,
        uint256 signature_algorithm,
        uint256 signature_algorithm_csca
    ) external override {
        if (!registry.checkRoot(bytes32(proof_csca.merkle_root))) {
            revert("Register__InvalidMerkleRoot");
        }
        // if (nullifiers[proof.nullifier]) {
        //     revert("YouAreUsingTheSameNullifierTwice");
        // }
        if (bytes32(proof.attestation_id) != attestationId) {
            revert("Register__InvalidAttestationId");
        }
        if (!verifyProofRegister(proof, signature_algorithm)) {
            revert("Register__InvalidProofRegister");
        }
        if (!verifyProofCSCA(proof_csca, signature_algorithm_csca)) {
            revert("Register__InvalidProofCSCA");
        }
        if (
            bytes32(proof.blinded_dsc_commitment) !=
            bytes32(proof_csca.blinded_dsc_commitment)
        ) {
            revert("Register__BlindedDSCCommitmentDontMatch");
        }

        nullifiers[proof.nullifier] = true;

        _addCommitment(proof.commitment);

        emit ProofValidated(
            proof_csca.merkle_root,
            proof.nullifier,
            proof.commitment
        );
    }

    function verifyProofRegister(
        RegisterProof calldata proof,
        uint256 signature_algorithm
    ) public view override returns (bool) {
        bool register_proof_result = IVerifier(verifiers[signature_algorithm])
            .verifyProof(
                proof.a,
                proof.b,
                proof.c,
                [
                    uint(proof.blinded_dsc_commitment),
                    uint(proof.nullifier),
                    uint(proof.commitment),
                    uint(proof.attestation_id)
                ]
            );
        return register_proof_result;
    }

    function verifyProofCSCA(
        CSCAProof calldata proof,
        uint256 signature_algorithm_csca
    ) public view override returns (bool) {
        bool csca_proof_result = IVerifierCSCA(
            cscaVerifier[signature_algorithm_csca]
        ).verifyProof(
                proof.a,
                proof.b,
                proof.c,
                [uint(proof.blinded_dsc_commitment), uint(proof.merkle_root)]
            );
        return csca_proof_result;
    }

    function _addCommitment(uint256 commitment) internal {
        uint256 index = getMerkleTreeSize();
        uint256 imt_root = imt._insert(commitment);
        merkleRootsCreated[imt_root] = true;
        emit AddCommitment(index, commitment, imt_root);
    }

    function checkRoot(uint256 root) external view returns (bool) {
        return merkleRootsCreated[root];
    }

    function getMerkleTreeSize() public view returns (uint256) {
        return imt.size;
    }

    function getMerkleRoot() public view returns (uint256) {
        return imt._root();
    }

    function indexOf(uint commitment) public view returns (uint256) {
        return imt._indexOf(commitment);
    }

    function addSignatureAlgorithm(
        uint256 signature_algorithm,
        address verifier_address
    ) external onlyOwner {
        require(
            verifier_address != address(0),
            "Register__InvalidVerifierAddress"
        );
        require(
            verifiers[signature_algorithm] == address(0),
            "Register__SignatureAlgorithmAlreadySet"
        );
        verifiers[signature_algorithm] = verifier_address;
    }

    function updateSignaturesAlgorithm(
        uint256 signature_algorithm,
        address verifier_address
    ) external onlyOwner {
        require(
            verifier_address != address(0),
            "Register__InvalidVerifierAddress"
        );
        verifiers[signature_algorithm] = verifier_address;
    }

    function addCSCAVerifier(
        uint256 signature_algorithm_csca,
        address _cscaVerifier
    ) external onlyOwner {
        require(
            _cscaVerifier != address(0),
            "Register__InvalidVerifierAddress"
        );
        cscaVerifier[signature_algorithm_csca] = _cscaVerifier;
    }

    function updateCSCAVerifier(
        uint256 signature_algorithm_csca,
        address _cscaVerifier
    ) external onlyOwner {
        require(
            _cscaVerifier != address(0),
            "Register__InvalidVerifierAddress"
        );
        cscaVerifier[signature_algorithm_csca] = _cscaVerifier;
    }

    function removeSignatureAlgorithm(
        uint256 signature_algorithm
    ) external onlyOwner {
        verifiers[signature_algorithm] = address(0);
    }

    function removeCSCAVerifier(
        uint256 signature_algorithm_csca
    ) external onlyOwner {
        cscaVerifier[signature_algorithm_csca] = address(0);
    }

    function devAddCommitment(uint commitment) external onlyOwner {
        _addCommitment(commitment);
    }
}
