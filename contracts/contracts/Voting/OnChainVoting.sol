pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract OnChainVoting is Ownable { 

    // Will be a users salt hashed;
    mapping(bytes32 => uint256) votes;
    uint256 votesCount = 0;

    // Will be token holder address to Encrypted(salt ++ vote) 
    mapping(address => bytes) submissions;
    uint256 submissionsCount = 0;

    uint256 result;
    uint256 endTime;

    // Security Token
    IERC20 public securityToken;

    constructor(
        IERC20 _securityToken, 
        address _issuer, 
        uint256 _endTime
    ) 
        public 
    {
        require(_securityToken != address(0), "Token address cannot be zero.");
        require(block.timestamp < _endTime);

        securityToken = _securityToken;
        endTime = _endTime;
        transferOwnership(_issuer);
    }


    /**********************************************
	* @dev function for every token holder to submit their vote
	* @param _encVote Encrypted userSalt concatenated with their vote, encrypted with votingAdmin's public key
    **********************************************/
    function placeVote(bytes _encVote) public  {
        require(securityToken.balanceOf(msg.sender) > 0, "Token Balance must be greater than 0");
        require(_encVote.length > 0, "Must submit a valid vote");
        require(block.timestamp < endTime, "Can only place vote before time is up");

        submissions[msg.sender] = encVote;
        submissionsCount += 1;
    }

/**********************************************
	* @dev function for votingAdmin to submit every vote
	* @param _usersSaltHash Array of hashes of users decrypted salt
    * @param _usersVote Array of plaintext value of users vote
    **********************************************/
    function submitUserVotes(
        bytes32[] _usersSaltHash, 
        uint256[] _usersVote
    )
        public 
        onlyOwner
    {
        require(_usersSaltHash.length == _usersVote.length, "Arrays must be same length");
        for (uint256 i = 0; i < _usersSaltHash.length; i++) {
            submitVote(_usersSaltHash[i], _usersVote[i]);
        }
        votesCount += _usersSaltHash.length;
    }

    /**********************************************
	* @dev function for votingAdmin to submit every vote
	* @param _userSaltHash Hash of users decrypted salt
    * @param _userVote Plaintext value of users vote
    **********************************************/
    function submitVote(
        bytes32 _userSaltHash, 
        uint256 _userVote
    )
        private
    {
        require(votes[_userSaltHash] == 0, "Cannot resubmit a users vote");
        votes[_userSaltHash] = _userVote; 
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
        require(submissionsCount == votesCount, "Must have correct number of submissions tallied to votes");
        require(result == 0, "May only submit the result once");
        require(block.timestamp > endTime, "Can only finalize once the voting has closed");
        result = _result;
    }

}