pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract OnChainVoting is Ownable { 

    // Will be a users salt hashed;
    mapping(bytes32 => uint256) vote;
    uint256 voteCount = 0;

    // Will be token holder address to Encrypted(salt ++ vote) 
    mapping(address => bytes) submissions;
    uint256 submissionsCount = 0;

    uint256 result;
    uint endTime;

    address votingAdmin;

    // Security Token
    IERC20 public securityToken;

    constructor(
        IERC20 _securityToken, 
        address _issuer, 
        address _votingAdmin,
        uint _endTime
    ) 
        public 
    {
        require(_securityToken != address(0), "Token addresses cannot be zero.");

        securityToken = _securityToken;
        votingAdmin = _votingAdmin;
        endTime = _endTime;
        transferOwnership(_issuer);
    }


    /**********************************************
	* @dev function for every token holder to submit their vote
	* @param _encVote Encrypted userSalt concatenated with their vote, encrypted with votingAdmin's public key
    * @param _sig 
    **********************************************/
    function placeVote(
        bytes _encVote, 
        bytes _sig
    ) 
        public  
    {
        require(securityToken.balanceOf(msg.sender) > 0, "Token Balance must be greater than 0");
        require(_encVote.length > 0, "Must submit a valid vote");
        require(block.timestamp < endTime, "Can only place vote before time is up");

        submissions[msg.sender] = encVote;
        submissionsCount += 1;
    }


    /**********************************************
	* @dev function for votingAdmin to submit every vote
	* @param _userSalt Hash of users decrypted salt
    * @param _userVote Plaintext value of users vote
    **********************************************/
    function submitVote(
        bytes32 _userSalt, 
        uint256 _userVote
    )
        public 
        onlyOwner
    {
        vote[_userSalt] = _userVote; 
        voteCount += 1;
    }


    /**********************************************
	* @dev function to publish final result of the vote
	* @param _result Hash of data that has been signed.  
    **********************************************/
    function finalizeVote(
        uint256 _result
    )
        public 
        onlyOwner 
    {
        require(submissionsCount == voteCount, "Must have correct number of submissions tallied ot votes");
        require(result == 0, "May only submit the result once");
        require(block.timestamp > endTime, "Can only finalize once the voting has closed");
        result = _result;
    }

}