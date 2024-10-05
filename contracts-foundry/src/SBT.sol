// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {Verifier_disclose} from "./verifiers/Verifier_disclose.sol";
import {Base64} from "./libraries/Base64.sol";
import {Formatter} from "./Formatter.sol";
import {Registry} from "./Registry.sol";
import {IRegister} from "./interfaces/IRegister.sol";

contract SBT is ERC721Enumerable, Ownable {
    using Strings for uint256;
    using Base64 for *;

    Verifier_disclose public immutable verifier;
    Formatter public formatter;
    IRegister public register;

    uint constant scope = 1;

    mapping(uint256 => bool) public nullifiers;

    struct SBTProof {
        uint nullifier;
        uint[3] revealedData_packed;
        uint attestation_id;
        uint merkle_root;
        uint scope;
        uint[6] current_date;
        uint user_identifier;
        uint[2] a;
        uint[2][2] b;
        uint[2] c;
    }

    struct AttributePosition {
        string name;
        uint256 start;
        uint256 end;
        uint256 index;
    }

    struct Attributes {
        string[8] values;
    }

    AttributePosition[] public attributePositions;

    mapping(uint256 => Attributes) private tokenAttributes;

    error CANNOT_TRANSFER_SBT();

    constructor(
        Verifier_disclose v,
        Formatter f,
        IRegister r
    ) 
        ERC721("OpenPassport", "OpenPassport") 
        Ownable(msg.sender)
    {
        verifier = v;
        formatter = f;
        register = r;
        setupAttributes();
        transferOwnership(msg.sender);
    }

    function setupAttributes() internal {
        attributePositions.push(AttributePosition("issuing_state", 2, 4, 0));
        attributePositions.push(AttributePosition("name", 5, 43, 1));
        attributePositions.push(
            AttributePosition("passport_number", 44, 52, 2)
        );
        attributePositions.push(AttributePosition("nationality", 54, 56, 3));
        attributePositions.push(AttributePosition("date_of_birth", 57, 62, 4));
        attributePositions.push(AttributePosition("gender", 64, 64, 5));
        attributePositions.push(AttributePosition("expiry_date", 65, 70, 6));
        attributePositions.push(AttributePosition("older_than", 88, 89, 7));
    }

    function mint(SBTProof calldata proof) public {
        require(
            register.checkRoot(uint(proof.merkle_root)),
            "Invalid merkle root"
        );
        // require(!nullifiers[proof.nullifier], "Signature already nullified");

        // require that the current date is valid
        // Convert the last four parameters into a valid timestamp, adding 30 years to adjust for block.timestamp starting in 1970
        uint[6] memory dateNum;
        for (uint i = 0; i < 6; i++) {
            dateNum[i] = proof.current_date[i];
        }
        uint currentTimestamp = getCurrentTimestamp(dateNum);

        // Check that the current date is within a +/- 1 day range
        require(
            currentTimestamp >= block.timestamp - 1 days &&
                currentTimestamp <= block.timestamp + 1 days,
            "Current date is not within the valid range"
        );

        require(
            verifier.verifyProof(
                proof.a,
                proof.b,
                proof.c,
                [
                    uint(proof.nullifier),
                    uint(proof.revealedData_packed[0]),
                    uint(proof.revealedData_packed[1]),
                    uint(proof.revealedData_packed[2]),
                    uint(proof.attestation_id),
                    uint(proof.merkle_root),
                    uint(proof.scope),
                    uint(proof.current_date[0]),
                    uint(proof.current_date[1]),
                    uint(proof.current_date[2]),
                    uint(proof.current_date[3]),
                    uint(proof.current_date[4]),
                    uint(proof.current_date[5]),
                    uint(proof.user_identifier)
                ]
            ),
            "Invalid Proof"
        );

        nullifiers[proof.nullifier] = true;

        // Effects: Mint token
        address addr = address(uint160(proof.user_identifier));
        uint256 newTokenId = totalSupply();
        _mint(addr, newTokenId);

        // Set attributes
        bytes memory charcodes = fieldElementsToBytes(
            proof.revealedData_packed
        );
        Attributes storage attributes = tokenAttributes[newTokenId];

        for (uint i = 0; i < attributePositions.length; i++) {
            AttributePosition memory attribute = attributePositions[i];
            bytes memory attributeBytes = new bytes(
                attribute.end - attribute.start + 1
            );
            for (uint j = attribute.start; j <= attribute.end; j++) {
                attributeBytes[j - attribute.start] = charcodes[j];
            }
            string memory attributeValue = string(attributeBytes);
            attributes.values[i] = attributeValue;
        }
    }

    function fieldElementsToBytes(
        uint256[3] memory publicSignals
    ) public pure returns (bytes memory) {
        uint8[3] memory bytesCount = [31, 31, 28];
        bytes memory bytesArray = new bytes(90); // 31 + 31 + 28

        uint256 index = 0;
        for (uint256 i = 0; i < 3; i++) {
            uint256 element = publicSignals[i];
            for (uint8 j = 0; j < bytesCount[i]; j++) {
                bytesArray[index++] = bytes1(uint8(element & 0xFF));
                element = element >> 8;
            }
        }

        return bytesArray;
    }

    function sliceFirstThree(
        uint256[12] memory input
    ) public pure returns (uint256[3] memory) {
        uint256[3] memory sliced;

        for (uint256 i = 0; i < 3; i++) {
            sliced[i] = input[i];
        }

        return sliced;
    }

    // function _beforeTokenTransfer(
    //     address from,
    //     address to,
    //     uint256 tokenId,
    //     uint256 batchSize
    // ) internal virtual {
    //     super._beforeTokenTransfer(from, to, tokenId, batchSize);
    //     require(
    //         from == address(0),
    //         "Cannot transfer - SBT is soulbound"
    //     );
    // }

    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
        revert CANNOT_TRANSFER_SBT();
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override(ERC721, IERC721) {
        revert CANNOT_TRANSFER_SBT();
    } 

    function isExpired(string memory date) public view returns (bool) {
        if (isAttributeEmpty(date)) {
            return false; // this is disregarded anyway in the next steps
        }
        uint256 expiryDate = formatter.dateToUnixTimestamp(date);

        return block.timestamp > expiryDate;
    }

    function getIssuingStateOf(
        uint256 _tokenId
    ) public view returns (string memory) {
        return tokenAttributes[_tokenId].values[0];
    }

    function getNameOf(uint256 _tokenId) public view returns (string memory) {
        return tokenAttributes[_tokenId].values[1];
    }

    function getPassportNumberOf(
        uint256 _tokenId
    ) public view returns (string memory) {
        return tokenAttributes[_tokenId].values[2];
    }

    function getNationalityOf(
        uint256 _tokenId
    ) public view returns (string memory) {
        return tokenAttributes[_tokenId].values[3];
    }

    function getDateOfBirthOf(
        uint256 _tokenId
    ) public view returns (string memory) {
        return tokenAttributes[_tokenId].values[4];
    }

    function getGenderOf(uint256 _tokenId) public view returns (string memory) {
        return tokenAttributes[_tokenId].values[5];
    }

    function getExpiryDateOf(
        uint256 _tokenId
    ) public view returns (string memory) {
        return tokenAttributes[_tokenId].values[6];
    }

    function getOlderThanOf(
        uint256 _tokenId
    ) public view returns (string memory) {
        return tokenAttributes[_tokenId].values[7];
    }

    function getCurrentTimestamp(
        uint256[6] memory dateNum
    ) public view returns (uint256) {
        string memory date = "";
        for (uint i = 0; i < 6; i++) {
            date = string(
                abi.encodePacked(date, bytes1(uint8(48 + (dateNum[i] % 10))))
            );
        }
        uint256 currentTimestamp = formatter.dateToUnixTimestamp(date);
        return currentTimestamp;
    }

    function isAttributeEmpty(
        string memory attribute
    ) private pure returns (bool) {
        for (uint i = 0; i < bytes(attribute).length; i++) {
            if (bytes(attribute)[i] != 0) {
                return false;
            }
        }
        return true;
    }

    function appendAttribute(
        bytes memory baseURI,
        string memory traitType,
        string memory value
    ) private view returns (bytes memory) {
        if (!isAttributeEmpty(value)) {
            baseURI = abi.encodePacked(
                baseURI,
                '{"trait_type": "',
                traitType,
                '", "value": "',
                formatAttribute(traitType, value),
                '"},'
            );
        }
        return baseURI;
    }

    function formatAttribute(
        string memory traitType,
        string memory value
    ) private view returns (string memory) {
        if (
            isStringEqual(traitType, "Issuing State") ||
            isStringEqual(traitType, "Nationality")
        ) {
            return formatter.formatCountryName(value);
        } else if (isStringEqual(traitType, "First Name")) {
            return formatter.formatName(value)[0];
        } else if (isStringEqual(traitType, "Last Name")) {
            return formatter.formatName(value)[1];
        } else if (
            isStringEqual(traitType, "Date of birth") ||
            isStringEqual(traitType, "Expiry date")
        ) {
            return formatter.formatDate(value);
        } else if (isStringEqual(traitType, "Older Than")) {
            return formatter.formatAge(value);
        } else if (isStringEqual(traitType, "Expired")) {
            return isExpired(value) ? "Yes" : "No";
        } else {
            return value;
        }
    }

    function isStringEqual(
        string memory a,
        string memory b
    ) public pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function substring(
        bytes memory str,
        uint startIndex,
        uint endIndex
    ) public pure returns (bytes memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return result;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view virtual override returns (string memory) {
        ownerOf(_tokenId);
        Attributes memory attributes = tokenAttributes[_tokenId];

        bytes memory baseURI = abi.encodePacked('{ "attributes": [');

        baseURI = appendAttribute(
            baseURI,
            "Issuing State",
            attributes.values[0]
        );
        baseURI = appendAttribute(baseURI, "First Name", attributes.values[1]);
        baseURI = appendAttribute(baseURI, "Last Name", attributes.values[1]);
        baseURI = appendAttribute(
            baseURI,
            "Passport Number",
            attributes.values[2]
        );
        baseURI = appendAttribute(baseURI, "Nationality", attributes.values[3]);
        baseURI = appendAttribute(
            baseURI,
            "Date of birth",
            attributes.values[4]
        );
        baseURI = appendAttribute(baseURI, "Gender", attributes.values[5]);
        baseURI = appendAttribute(baseURI, "Expiry date", attributes.values[6]);
        baseURI = appendAttribute(baseURI, "Expired", attributes.values[6]);
        baseURI = appendAttribute(baseURI, "Older Than", attributes.values[7]);

        // Remove the trailing comma if baseURI has one
        if (
            keccak256(abi.encodePacked(baseURI[baseURI.length - 1])) ==
            keccak256(abi.encodePacked(","))
        ) {
            baseURI = substring(baseURI, 0, bytes(baseURI).length - 1);
        }

        baseURI = abi.encodePacked(
            baseURI,
            '],"description": "OpenPassport guarantees possession of a valid passport.","external_url": "https://openpassport.app","image": "https://i.imgur.com/9kvetij.png","name": "OpenPassport #',
            _tokenId.toString(),
            '"}'
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    baseURI.encode()
                )
            );
    }
}
