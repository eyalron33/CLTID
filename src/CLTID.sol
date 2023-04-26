// contracts/Woolball.sol
// SPDX-License-Identifier: MIT

pragma solidity >=0.8.17;

import "./LockedCommanderToken.sol";
import "./StringUtils.sol";

import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @dev CLTID (Commander-Locked Token ID) contract
 * @dev An ID system based on Commander Token and Locked Token standard
 */
contract CLTID is CLT, Ownable {

    struct Name {
        address     resolver;
        uint256     expirationTimestamp;
    }

    // A mapping of nameID to Name
    mapping(uint256 => Name) private _names;

    modifier onlyNameOwner(uint256 nameId) {
        require(ownerOf(nameId) == msg.sender, "Sender is not the owner of the name.");
        _;
    }

    modifier nameIdExists(uint256 nameId) {
        require(_names[nameId].expirationTimestamp > block.timestamp, "Woolball: nameId doesn't exist");
        _;
    }

    modifier validName(string calldata name) {
        require( !StringUtils.isCharInString(name, "&"), "Woolball: name can't have '&' characters within in"  );
        _;
    }

    /**
     * @dev Constructs a new CLTID registry.
     */
    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(
        string memory name,
        string memory symbol
    ) CLT(name, symbol) {}

    /**
     * @dev Registers a new name. May only be called by the owner of the registry.
     * @param name The name to register.
     * @param owner the address of the owner of the new name.
     * @param expirationTimestamp The expiration date of the name.
     */
    function newName(string calldata name, address owner, uint256 expirationTimestamp) public virtual onlyOwner validName(name) returns (uint256) {

        uint256 nameId = uint256(sha256(abi.encodePacked(name)));

        // check that the name is unregistered
        require( _names[nameId].expirationTimestamp < block.timestamp, "Woolball: name is already registered");

        // check that expirationTimestamp is in the future
        require( expirationTimestamp > block.timestamp, "Woolball: expirationTimestamp is in the past");        

        _mint(owner, nameId);

        _names[nameId].expirationTimestamp = expirationTimestamp;

        // emit NewName(name, nameId, owner);

        return nameId;
    }

     function setExpirationDate(uint256 nameId, uint256 newTimeStamp) public virtual onlyOwner nameIdExists(nameId) {
        // check that the nameId is a Woolball name (not link or thread), and is is registered
        require(_names[nameId].expirationTimestamp > 0, "Woolball: nameId must be of a registered Woolball name");

        _names[nameId].expirationTimestamp = newTimeStamp;
    }

    /**
     * @dev Sets the resolver address for the specified name.
     * @param nameId The name to update.
     * @param nameResolver The address of the resolver.
     */
    function setResolver(
        uint256 nameId,
        address nameResolver
    ) public virtual onlyNameOwner(nameId) {
        _names[nameId].resolver = nameResolver;

        // emit NewResolver(nameId, resolver);
    }

    /**
     * @dev Returns the address of the resolver for the specified name.
     * @param nameId The specified name.
     * @return address of the resolver.
     */
    function resolver(uint256 nameId) public view virtual nameIdExists(nameId) returns (address) {
        return _names[nameId].resolver;
    }
}
