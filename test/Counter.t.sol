// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/CTID.sol";

contract CLTIDTest is Test {
		CTID CTIDContract = new CTID("CTLID", "CTLID");    

		function testNewName() public {
			uint256 nameId = CTIDContract.newName("neiman", 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84, 1682424133);
			address ownerOfName = CTIDContract.ownerOf(nameId);
			assertEq(ownerOfName, 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);
		}
}
