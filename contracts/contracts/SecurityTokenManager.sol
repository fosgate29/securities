pragma solidity 0.4.24; 

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./SecurityToken.sol";

/* This contract will be a central contract from which to manage the security token, a an on chain sale if applicaiton, 
on chain distributions, voting mechanisms, and information dissemination (if applicable). */

contract SecurityTokenManager is Ownable {

    constructor(
        uint256 _initialSupply,
        string _name,
        string _symbol,
        uint8 _decimals, 
        address _issuer
    ) public {

    }

    //Deploy or link security allocation contract

    //Deploy or link sales contract - regular ETH and/or stable coin

    //Deploy dividends contract - could be pik or stable coin

}