// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/CLTID.sol";


contract CLTIDTest is Test {
		CLTID CLTIDContract = new CLTID("CTLID", "CTLID");  
		CLTID CLTIDContract2 = new CLTID("CTLID", "CTLID");  

		uint256 expirationName = 1982424133;


		// sanity test of creating a new name
		function testNewName() public {
			uint256 nameId = CLTIDContract.newName("satoshi", 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84, 1682424133);
			address ownerOfName = CLTIDContract.ownerOf(nameId);
			assertEq(ownerOfName, 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);
		}

		// testing the lock mechanism
		function testLockAndTransferNames() public {
			// create three names in CLTIDContract
			uint256 nameId1 = CLTIDContract.newName("satoshi", address(this), expirationName);
			uint256 nameId2 = CLTIDContract.newName("hal", address(this), expirationName);
			uint256 nameId3 = CLTIDContract.newName("anonymous", address(this), expirationName);

			// create a name in a different name system
			uint256 nameIdOtherSystem = CLTIDContract2.newName("Joybubbles", address(this), expirationName);

			// lock "hal" to "satoshi"
			CLTIDContract.lock(nameId2, address(CLTIDContract), nameId1);

			// lock Joybubbles (from another name system) to hal
			CLTIDContract2.lock(nameIdOtherSystem, address(CLTIDContract), nameId2);

			// check that double locking fails
			vm.expectRevert(bytes("Locked Token: Deadlock deteceted! LockingId is locked to tokenId"));
			CLTIDContract.lock(nameId1, address(CLTIDContract), nameId2);

			// check that a locked name can't be transferred
			vm.expectRevert(bytes("Locked Token: tokenId is locked and caller is not the contract holding the locking token"));
			CLTIDContract.transferFrom(address(this), 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84, nameId2);

			// transfer the first name
			CLTIDContract.transferFrom(address(this), 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84, nameId1);

			// check that it transferred the two locked names
			address ownerofName2 = CLTIDContract.ownerOf(nameId2);
			address ownerOfNameOtherSystem = CLTIDContract2.ownerOf(nameIdOtherSystem);
			assertEq(ownerofName2, 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);
			assertEq(ownerOfNameOtherSystem, 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);

			// check that the unlocked name was not transferred
			address ownerofName3 = CLTIDContract.ownerOf(nameId3);
			assertEq(ownerofName3, address(this));

			// check that locking of names with different owners fail
			vm.expectRevert(bytes("Locked Token: the tokens do not have the same owner"));
			CLTIDContract.lock(nameId3, address(CLTIDContract), nameId1);
		}

		function testDependence() public {
			address poorProject = 0x9FA6312471ceEa9936eEFf2AE7b4a3678fa59685;
			address richDAO = 0x9D49aa8F934Ab071429A8f3dAC3B99e558277374;
			address thirdInnocentParty = 0xa2e8C4583a14E9A1e401f9c8304F713A27880141;

			// create names
			uint256 nameIdPoorProject = CLTIDContract.newName("poorProject", poorProject, expirationName);
			uint256 nameIdAgreementToken = CLTIDContract.newName("agreementToken", richDAO, expirationName);

			// set agreementToken to nontransferable
			vm.prank(richDAO);
			CLTIDContract.setTransferable(nameIdAgreementToken, false);

			
			//make poorProject dependent on AgreementToken
			vm.prank(poorProject);
			CLTIDContract.setDependence(nameIdPoorProject, address(CLTIDContract), nameIdAgreementToken);

			// try to transfer poorProject to see it fails
			vm.prank(poorProject);
			vm.expectRevert(bytes("CLT: the token depends on at least one nontransferable token"));
			CLTIDContract.transferFrom(poorProject, thirdInnocentParty, nameIdPoorProject);

			// to remove dependence, richDAO needs first to make the token transferable
			vm.prank(richDAO);
			CLTIDContract.setTransferable(nameIdAgreementToken, true);

			// remove poorProject dependence on AgreementToken
			vm.prank(poorProject);
			CLTIDContract.removeDependence(nameIdPoorProject, address(CLTIDContract), nameIdAgreementToken);

			// check that poorProject can transfer nameIdPoorProject
			vm.prank(poorProject);
			CLTIDContract.transferFrom(poorProject, thirdInnocentParty, nameIdPoorProject);
		}
}
