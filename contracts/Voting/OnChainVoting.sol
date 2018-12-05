pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract OnChainVoting is Ownable { 
    using SafeMath for uint256;

    // To be updated as votes are submitted to the chain.
    // Mapping of a voter's address to Encrypted(salt ++ vote).
    mapping(address => bytes) submissions;
    uint256 submissionsCount = 0;

    // To be updated as the issuer verifies the vote's result on chain.
    // Mapping of hash(salt) for a user to their vote.
    // For a private vote, user's votes would be bytes not uint256
    mapping(bytes32 => uint256) votes;
    uint256 votesCount = 0;

    uint256 result;
    uint256 endTime;

    IERC20 public securityToken;

    modifier isAfterEndTime {
        require(now >= endTime, "The vote has not yet ended");
        _;
    }

	/**
	* @dev Constructor to initialize the contract.
	* @param _securityToken The address of the security token contract.
    * @param _issuer The address of the security issuer.
    * @param _endTime The time at which the vote will close.
	*/
    constructor(
        IERC20 _securityToken, 
        address _issuer, 
        uint256 _endTime
    ) 
        public 
    {
        require(_securityToken != address(0), "Token address cannot be zero.");
        require(now < _endTime, "The end time must be in the future");
        require(_issuer != address(0), "Issuer address cannot be zero.");

        securityToken = _securityToken;
        endTime = _endTime;
        transferOwnership(_issuer);
    }


    /**
	* @dev Function for every token holder to submit their vote.
	* @param _encVote Encryption of user's salt concatenated with their vote, encrypted with issuer's public key.
    */
    function placeVote(bytes _encVote) public {
        require(securityToken.balanceOf(msg.sender) > 0, "The sender's token balance must be greater than 0");
        require(_encVote.length > 0, "Must submit a valid vote");
        require(now < endTime, "The vote has end time has been reached");
        require(submissions[msg.sender] = 0, "The voter has already voted");

        // Store the vote submission and track the number of submissions
        submissions[msg.sender] = _encVote;
        submissionsCount += 1;
    }

    /**
	* @dev Function for the issuer to release every plaintext vote back on-chain.
    * @dev For a private vote, user's votes would be bytes not uint256
	* @param _usersSaltHash Array of hash(salt) for each user.
    * @param _usersVote Array of plaintext values of users vote
    */
    function submitUserVotes(
        bytes32[] _usersSaltHash, 
        uint256[] _usersVote
    )
        public 
        onlyOwner
        isAfterEndTime
    {
        require(_usersSaltHash.length == _usersVote.length, "Arrays must be same length");
        require(_usersSaltHash.length != 0, "The arrays cannot be empty");

        // Stores each user's vote anonymously on-chain
        for (uint256 i = 0; i < _usersSaltHash.length; i++) {
            submitVote(_usersSaltHash[i], _usersVote[i]);
        }
        // Tracking the number of votes submitted on-chain
        votesCount += _usersVote.length;
    }

    /**
	* @dev Function for the issuer to submit every vote on-chain
    * @dev For a private vote, user's votes would be bytes not uint256
	* @param _userSaltHash Hash of user's salt
    * @param _userVote Plaintext value of users vote
    */
    function submitVote(
        bytes32 _userSaltHash, 
        uint256 _userVote
    )
        private
    {
        require(votes[_userSaltHash] == 0, "Cannot resubmit a users vote");
        votes[_userSaltHash] = _userVote; 
    }


    /**
	* @dev Function to publish final result of the vote
    * @dev This must happen after all individual votes have been submitted
    * @dev For a private vote, the result would be bytes not uint256
	* @param _result The result of the vote.  
    */
    function finalizeVote(
        uint256 _result
    )
        public 
        onlyOwner
        isAfterEndTime 
    {
        require(submissionsCount == votesCount, "Must have correct number of submissions tallied to votes cast");
        require(result == 0, "May only submit the result once");
        result = _result;
    }

}