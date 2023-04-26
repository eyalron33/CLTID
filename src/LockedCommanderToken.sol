// SPDX-License-Identifier: MIT

pragma solidity >=0.8.17;

import "./interfaces/ICommanderToken.sol";
import "./interfaces/ILockedToken.sol";
import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

import "forge-std/console.sol";


/**
 * @title LCT: Locked Commander Token, a token implementing both Commander and Locked Tokens interface
 * @author Eyal Ron
 */
contract LCT is ICommanderToken, ILockedToken, ERC721 {
    struct ExternalToken {
        address tokensCollection;
        uint256 tokenId;
    }

    struct LCToken {
        bool nontransferable;
        bool nonburnable;

        // The Commander Tokens this CToken struct depends on
        ExternalToken[] dependencies;
        
        // A mapping to manage the indices of "dependencies"
        mapping(address => mapping(uint256 => uint256)) dependenciesIndex;

        // A whitelist of addresses the token can be transferred to regardless of the value of "nontransferable"
        // Note: an address can be whitelisted but the token still won't be transferable to this address
        // if it depends on a nontransferable token
        mapping(address => bool) whitelist;

        ExternalToken[] lockedTokens; // array of tokens locked to this token
        
        // A mapping to manage the indices of "lockedTokens"
        mapping(address => mapping(uint256 => uint256)) lockingsIndex;

        // 0 if this token is unlocked, or otherwise holds the information of the locking token
        ExternalToken locked;
    }

    modifier approvedOrOwner(uint256 tokenId) {
        require(
            _isApprovedOrOwner(msg.sender, tokenId),
            "ERC721: caller is not token owner or approved"
        );
        _;
    }

    // verifies that two tokens have the same owner
    modifier sameOwner(
        uint256 token1Id,
        address Token2ContractAddress,
        uint256 Token2Id
    ) {
        require(
            ERC721.ownerOf(token1Id) == ERC721(Token2ContractAddress).ownerOf(Token2Id),
            "Locked Token: the tokens do not have the same owner"
        );
        _;
    }

    modifier onlyContract(address contractAddress) {
        require(
            contractAddress == msg.sender,
            "Locked Token: transaction is not sent from the correct contract"
        );
        _;
    }

    modifier isApproveOwnerOrLockingContract(uint256 tokenId) {
        (, uint256 lockedCT) = isLocked(tokenId);
        if (lockedCT > 0)
            require(
                msg.sender == address(_tokens[tokenId].locked.tokensCollection),
                "Locked Token: tokenId is locked and caller is not the contract holding the locking token"
            );
        else
            require(
                _isApprovedOrOwner(_msgSender(), tokenId),
                "ERC721: caller is not token owner or approved"
            );
        _;
    }

    // LCT ID -> token's data
    mapping(uint256 => LCToken) private _tokens;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {}


    /***********************************************
     * Dependency Functions for Commander Token    *
     ***********************************************/
    /**
     * @dev Adds to tokenId dependency on CTId from contract CTContractAddress.
     * @dev A token can be transfered or burned only if all the tokens it depends on are transferable or burnable, correspondingly.
     * @dev The caller must be the owner, opertaor or approved to use tokenId.
     */
    function setDependence(
        uint256 tokenId,
        address CTContractAddress,
        uint256 CTId
    )
        public
        virtual
        override
        approvedOrOwner(tokenId)
    {
        // checks that tokenId is not dependent already on CTId
        require(
            _tokens[tokenId].dependenciesIndex[CTContractAddress][CTId] == 0,
            "LCT: tokenId already depends on CTid from CTContractAddress"
        );

        // creates ExternalCommanderToken variable to express the new dependency
        ExternalToken memory newDependency;
        newDependency.tokensCollection = CTContractAddress;
        newDependency.tokenId = CTId;

        // saves the index of the new dependency
        // we need to add '1' to the index since the first index is '0', but '0' is also 
        // the default value of uint256, so if we add '1' in
        // order to differentiate the first index from an empty mapping entry.
        _tokens[tokenId].dependenciesIndex[CTContractAddress][CTId] =
            _tokens[tokenId].dependencies.length+1;

        // adds dependency
        _tokens[tokenId].dependencies.push(newDependency);

        emit NewDependence(tokenId, CTContractAddress, CTId);
    }

    /**
     * @dev Removes from tokenId the dependency on CTId from contract CTContractAddress.
     */
    function removeDependence(
        uint256 tokenId,
        address CTContractAddress,
        uint256 CTId
    ) public virtual override {
        // casts CTContractAddress to type ICommanderToken 
        ICommanderToken CTContract = ICommanderToken(CTContractAddress);

        // checks that tokenId is indeed dependent on CTId
        require(
            _tokens[tokenId].dependenciesIndex[CTContractAddress][CTId] > 0,
            "LCT: tokenId is not dependent on CTid from contract CTContractAddress"
        );

        // CTContractAddress can always remove the dependency, but the owner 
        // of tokenId can remove it only if CTId is transferable & burnable
        require(
            ( _isApprovedOrOwner(msg.sender, tokenId) &&
            CTContract.isTransferable(CTId) &&
            CTContract.isBurnable(CTId) ) ||
            ( msg.sender == CTContractAddress ),
            "LCT: sender is not permitted to remove dependency"
        );

        // gets the index of the token we are about to remove from dependencies
        // we remove '1' because we added '1' when saving the index in setDependence, 
        // see the comment in setDependence for an explanation
        uint256 dependencyIndex = _tokens[tokenId].dependenciesIndex[CTContractAddress][CTId]-1;

        // clears dependenciesIndex for this token
        delete _tokens[tokenId].dependenciesIndex[CTContractAddress][CTId];

        // removes dependency: copy the last element of the array to the place of 
        // what was removed, then remove the last element from the array
        uint256 lastDependecyIndex = _tokens[tokenId].dependencies.length - 1;
        _tokens[tokenId].dependencies[dependencyIndex] = _tokens[tokenId]
            .dependencies[lastDependecyIndex];
        _tokens[tokenId].dependencies.pop();

        emit RemovedDependence(tokenId, CTContractAddress, CTId);
    }

    /**
     * @dev Checks if tokenId depends on CTId from CTContractAddress.
     **/
    function isDependent(
        uint256 tokenId,
        address CTContractAddress,
        uint256 CTId
    ) public view virtual override returns (bool) {
        return
            _tokens[tokenId].dependenciesIndex[CTContractAddress][CTId] > 0
                ? true
                : false;
    }

    /**
     * @dev Sets the transferable property of tokenId.
     **/
    function setTransferable(
        uint256 tokenId,
        bool transferable
    ) public virtual override approvedOrOwner(tokenId) {
        _tokens[tokenId].nontransferable = !transferable;
    }

    /**
     * @dev Sets the burnable status of tokenId.
     **/
    function setBurnable(
        uint256 tokenId,
        bool burnable
    ) public virtual override approvedOrOwner(tokenId) {
        _tokens[tokenId].nonburnable = !burnable;
    }

    /**
     * @dev Checks the transferable property of tokenId 
     * @dev (only of the token itself, not of its dependencies).
     **/
    function isTransferable(
        uint256 tokenId
    ) public view virtual override returns (bool) {
        return !_tokens[tokenId].nontransferable;
    }

    /**
     * @dev Checks the burnable property of tokenId 
     * @dev (only of the token itself, not of its dependencies).
     **/
    function isBurnable(
        uint256 tokenId
    ) public view virtual override returns (bool) {
        return !_tokens[tokenId].nonburnable;
    }

    /**
     * @dev Checks if all the tokens that tokenId depends on are transferable or not 
     * @dev (only of the dependencies, not of the token).
     **/
    function isDependentTransferable(
        uint256 tokenId
    ) public view virtual override returns (bool) {
        for (uint256 i = 0; i < _tokens[tokenId].dependencies.length; i++) {
            ICommanderToken CTContract = ICommanderToken(_tokens[tokenId]
                .dependencies[i]
                .tokensCollection);
            uint256 CTId = _tokens[tokenId].dependencies[i].tokenId;
            if (!CTContract.isTokenTransferable(CTId)) {
                return false;
            }
        }

        return true;
    }

    /**
     * @dev Checks all the tokens that tokenId depends on are burnable 
     * @dev (only of the dependencies, not of the token).
     **/
    function isDependentBurnable(
        uint256 tokenId
    ) public view virtual override returns (bool) {
        for (uint256 i = 0; i < _tokens[tokenId].dependencies.length; i++) {
            ICommanderToken CTContract = ICommanderToken(_tokens[tokenId]
                .dependencies[i]
                .tokensCollection);
            uint256 CTId = _tokens[tokenId].dependencies[i].tokenId;
            if (!CTContract.isTokenBurnable(CTId)) {
                return false;
            }
        }

        return true;
    }

    /**
     * @dev Checks if tokenId can be transferred 
     * @dev (meaning, both the token itself and all of its dependncies are transferable).
     **/
    function isTokenTransferable(
        uint256 tokenId
    ) public view virtual override returns (bool) {
        return isTransferable(tokenId) && isDependentTransferable(tokenId);
    }

    /**
     * @dev Checks if tokenId can be burned.
     * @dev (meaning, both the token itself and all of its dependncies are transferable).
     **/
    function isTokenBurnable(
        uint256 tokenId
    ) public view virtual override returns (bool) {
        return isBurnable(tokenId) && isDependentBurnable(tokenId);
    }

    /********************************************
     * Whitelist functions for Commander Token  *
     ********************************************/

     /**
      * @dev Adds or removes an address from the whitelist of tokenId.
      * @dev tokenId can be transferred to whitelisted addresses even when its set to be nontransferable.
      **/
    function setTransferWhitelist(
        uint256 tokenId, 
        address whitelistAddress,
        bool    isWhitelisted
    ) public virtual override approvedOrOwner(tokenId) {
        _tokens[tokenId].whitelist[whitelistAddress] = isWhitelisted;
    }

    /**
     * @dev Checks if an address is whitelisted.
     **/
    function isAddressWhitelisted(
        uint256 tokenId, 
        address whitelistAddress
    ) public view virtual override returns (bool) {
        return _tokens[tokenId].whitelist[whitelistAddress];
    }

    /**
      * @dev Checks if tokenId can be transferred to addressToTransferTo, without taking its dependence into consideration.
      **/
    function isTransferableToAddress(
        uint256 tokenId, 
        address addressToTransferTo
    ) public view virtual override returns (bool) {
        // either token is transferable (to all addresses, and specifically to 'addressToTransferTo') 
        // or otherwise the address is whitelisted
        return (isTransferable(tokenId) || _tokens[tokenId].whitelist[addressToTransferTo]);
    }
    
    /**
      * @dev Checks if all the dependences of tokenId can be transferred to addressToTransferTo,
      **/
    function isDependentTransferableToAddress(
        uint256 tokenId, 
        address transferToAddress
    ) public view virtual override returns (bool) {
        for (uint256 i = 0; i < _tokens[tokenId].dependencies.length; i++) {
            ICommanderToken STContract = ICommanderToken(_tokens[tokenId]
                .dependencies[i]
                .tokensCollection);
            uint256 STId = _tokens[tokenId].dependencies[i].tokenId;

            if (!STContract.isTokenTransferableToAddress(STId, transferToAddress)) {
                return false;
            }
        }

        return true;
    }

    /**
      * @dev Checks if tokenId can be transferred to addressToTransferTo.
      **/
    function isTokenTransferableToAddress(
        uint256 tokenId, 
        address transferToAddress
    ) public view virtual override returns (bool) {
        return isTransferableToAddress(tokenId, transferToAddress) && isDependentTransferableToAddress(tokenId, transferToAddress);
    }


    /***********************************************
     * Locked Token functions                      *
     ***********************************************/
    /**
     * @dev Locks tokenId tokenId to token LockingId from LockingContract. Both tokens must have the same owner.
     * @dev 
     * @dev With such a lock in place, tokenId transfer and burn functions can't be called by
     * @dev its owner as long as the locking is in place.
     * @dev 
     * @dev If LckingId is transferred or burned, it also transfers or burns tokenId.
     * @dev If tokenId is nontransferable or unburnable, then a call to the transfer or
     * @dev burn function of the LockingId unlocks the tokenId.
     */
    function lock(
        uint256 tokenId,
        address LockingContract,
        uint256 LockingId
    )
        public
        virtual
        override
        approvedOrOwner(tokenId)
        sameOwner(tokenId, LockingContract, LockingId)
    {
        // check that tokenId is unlocked
        (address LockedContract, uint256 lockedCT) = isLocked(tokenId);
        require(lockedCT == 0, "Locked Token: token is already locked");

        // Check that LockingId is not locked to tokenId, otherwise the locking enters a deadlock.
        // Warning: A deadlock migt still happen if LockingId might is locked to another token 
        // which is locked to tokenId, but we leave this unchecked, so be careful using this.
        (LockedContract, lockedCT) = ILockedToken(LockingContract).isLocked(LockingId);
        require(LockedContract != address(this) || lockedCT != tokenId, 
            "Locked Token: Deadlock deteceted! LockingId is locked to tokenId");

        // lock token
        _tokens[tokenId].locked.tokensCollection = LockingContract;
        _tokens[tokenId].locked.tokenId = LockingId;

        // nofity LockingId in LockingContract that tokenId is locked to it
        ILockedToken(LockingContract).addLockedToken(LockingId, address(this), tokenId);

        emit NewLocking(tokenId, LockingContract, LockingId);
    }

    /**
     * @dev unlocks a a token.
     * @dev This function must be called from the contract that locked tokenId.
     */
    function unlock(
        uint256 tokenId
    )
        public
        virtual
        override
        onlyContract(address(_tokens[tokenId].locked.tokensCollection))
    {
        // remove locking
        _tokens[tokenId].locked.tokensCollection = address(0);
        _tokens[tokenId].locked.tokenId = 0;

        emit Unlocked(tokenId);
    }

    /**
     * @dev returns (0x0, 0) if token is unlocked or the locking token (contract and id) otherwise
     */
    function isLocked(
        uint256 tokenId
    ) public view virtual override returns (address, uint256) {
        return (
            _tokens[tokenId].locked.tokensCollection,
            _tokens[tokenId].locked.tokenId
        );
    }

    /**
     * @dev addLockedToken notifies a Token that another token (LockedId), with the same owner, is locked to it.
     */
    function addLockedToken(
        uint256 tokenId,
        address LockedContract,
        uint256 LockedId
    )
        public
        virtual
        override
        sameOwner(tokenId, LockedContract, LockedId)
        onlyContract(LockedContract)
    {
        // check that LockedId from LockedContract is not locked already to tokenId
        require(
            _tokens[tokenId].lockingsIndex[LockedContract][LockedId] == 0,
            "Locked Token: tokenId is already locked to LockedId from contract LockedContract"
        );

        // create ExternalToken variable to express the locking
        ExternalToken memory newLocking;
        newLocking.tokensCollection = LockedContract;
        newLocking.tokenId = LockedId;

        // save the index of the new dependency
        // we need to add '1' to the index since the first index is '0', but '0' is also 
        // the default value of uint256, so if we add '1' in
        // order to differentiate the first index from an empty mapping entry.
        _tokens[tokenId].lockingsIndex[LockedContract][LockedId] = _tokens[tokenId]
            .lockedTokens
            .length+1;

        // add a locked token
        _tokens[tokenId].lockedTokens.push(newLocking);
    }

    /**
     * @dev removeLockedToken removes a token that was locked to the tokenId.
     */
    function removeLockedToken(
        uint256 tokenId,
        address LockedContract,
        uint256 LockedId
    ) public virtual override {
        // check that LockedId from LockedContract is indeed locked to tokenId
        require(
            _tokens[tokenId].lockingsIndex[LockedContract][LockedId] > 0,
            "Locked Token: LockedId in contract LockedContract is not locked to tokenId"
        );

        // get the index of the token we are about to remove from locked tokens
        // we remove '1' because we added '1' when saving the index in addLockedToken, 
        // see the comment in addLockedToken for an explanation
        uint256 lockIndex = _tokens[tokenId].lockingsIndex[LockedContract][LockedId] - 1;

        // clear lockingsIndex for this token
        _tokens[tokenId].lockingsIndex[LockedContract][LockedId] = 0;

        // remove locking: copy the last element of the array to the place of what was removed, then remove the last element from the array
        uint256 lastLockingsIndex = _tokens[tokenId].lockedTokens.length - 1;
        _tokens[tokenId].lockedTokens[lockIndex] = _tokens[tokenId].lockedTokens[
            lastLockingsIndex
        ];
        _tokens[tokenId].lockedTokens.pop();

        // notify LockedContract that locking was removed
        ILockedToken(LockedContract).unlock(LockedId);
    }

    /**************************************************************
     * Burn function is in both ICommanderToken and ILockedToken  *
     **************************************************************/
    /**
     * @dev burns tokenId.
     * @dev isTokenBurnable must return 'true'.
     **/
    function burn(uint256 tokenId) public virtual override(ICommanderToken, ILockedToken) approvedOrOwner(tokenId) {
        require(isTokenBurnable(tokenId), "LCT: the token or one of its Commander Tokens are not burnable");

        // burn each token locked to tokenId 
        // if the token is unburnable, then simply unlock it
        for (uint i; i < _tokens[tokenId].lockedTokens.length; i++) {
            ILockedToken STContract = ILockedToken(_tokens[tokenId]
                .lockedTokens[i]
                .tokensCollection);
            uint256 STId = _tokens[tokenId].lockedTokens[i].tokenId;
            STContract.burn(STId);
        }

        // 'delete' in solidity doesn't work on mappings, so we delete the lockingsIndex mapping items manually
        for (uint i=0; i<_tokens[tokenId].lockedTokens.length; i++) {
            ExternalToken memory CT =  _tokens[tokenId].lockedTokens[i];
            delete _tokens[tokenId].lockingsIndex[address(CT.tokensCollection)][CT.tokenId];
        }


        // 'delete' in solidity doesn't work on mappings, so we delete the dependenciesIndex mapping items manually
        for (uint i=0; i<_tokens[tokenId].dependencies.length; i++) {
            ExternalToken memory CT =  _tokens[tokenId].dependencies[i];
            delete _tokens[tokenId].dependenciesIndex[address(CT.tokensCollection)][CT.tokenId];
        }

        // delete the rest
        delete _tokens[tokenId];

        // TODO: whitelist of Commander Token is NOT deleted since we don't hold the indices of this mapping
        // TODO: consider fixing this in a later version
    }

    /***********************************************
     * Overrided functions from ERC165 and ERC721  *
     ***********************************************/
     /**
     * @dev we reimplement this function to add the isApproveOwnerOrLockingContract modifier
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override(IERC721, ERC721) isApproveOwnerOrLockingContract(tokenId) {
        //solhint-disable-next-line max-line-length

        ERC721._transfer(from, to, tokenId);
    }

    /**
     * @dev we reimplement this function to add the isApproveOwnerOrLockingContract modifier
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override(IERC721, ERC721) isApproveOwnerOrLockingContract(tokenId) {

        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting and burning. If {ERC721Consecutive} is
     * used, the hook may be called as part of a consecutive (batch) mint, as indicated by `batchSize` greater than 1.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s tokens will be transferred to `to`.
     * - When `from` is zero, the tokens will be minted for `to`.
     * - When `to` is zero, ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     * - `batchSize` is non-zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        ERC721._beforeTokenTransfer(from, to, tokenId, batchSize);

        require(
                isTransferableToAddress(tokenId, to),
                "LCT: the token status is set to nontransferable"
            );

        require(
                isDependentTransferableToAddress(tokenId, to),
                "LCT: the token depends on at least one nontransferable token"
            );

        // transfer each token locked to tokenId 
        // if the token is nontransferable, then simply unlock it
        for (uint i; i < _tokens[tokenId].lockedTokens.length; i++) {
            ILockedToken STContract = ILockedToken(_tokens[tokenId]
                .lockedTokens[i]
                .tokensCollection);
            uint256 STId = _tokens[tokenId].lockedTokens[i].tokenId;
            STContract.transferFrom(from, to, STId);
        }
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721, IERC165) returns (bool) {
        return
            interfaceId == type(ICommanderToken).interfaceId ||
            interfaceId == type(ILockedToken).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
