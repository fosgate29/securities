pragma solidity 0.4.24; 

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

contract StableCoinPayments is Ownable {

    using ECDSA for bytes32; 
    using SafeMath for uint256;

    enum ChallengeState { NoChallenge, Challenged, Resolved }

    struct Payment {
        // Payment allocated at this time
        uint256 timestamp;
        // Amount of tokens to be disbursed
        uint256 value;
        //Storing challenge state in struct for now, defaults to NoChallenge
        ChallengeState state; 
    }


    event PaymentAllocated(address _securityHolder, uint256 _paymentAmount);
    event PaymentChallenged(address _securityHolder, uint256 _paymentAmount, uint256 _securityAmountOwned);
    event PaymentResolved(address _securityHolder, uint256 _newPaymentAmount);
    
    //Challenge period set to two weeks
    uint256 public constant CHALLENGE_PERIOD = 2 weeks;  

    //Address will be per each security token holder
    mapping(address => Payment[]) public payments;

    //Address of security token, required for checking the balance of security tokens per holder
    IERC20 public securityToken;
    IERC20 public stableCoin; 

    /**
	* @dev Constructor to initialize the contract.
	* @param _securityToken Address of security token with which to apply Payment.
    * @param _stableCoin Address of stable coin with which to pay Payment. 
    * @param _issuer Address of issuer or whomever will be managing Payment. 
	*/
    constructor(IERC20 _securityToken, IERC20 _stableCoin, address _issuer) public {
        require(_securityToken != address(0) && _stableCoin != address(0), "Token addresses cannot be zero.");
        securityToken = _securityToken;
        stableCoin = _stableCoin; 
        transferOwnership(_issuer);    
    }
    
    /**
	* @dev Allows issuer to allocate Payment to security holders.
	* @param _holders Array of addresses that are security token holders. 
    * @param _PaymentPerShare The Payment per share or security token, used to calcuate total Payment owed. 
    * Issuer must approver this contract to transfer their stable coin prior to this transaction.
    */
    function allocatePayment(address[] _holders, uint256 _paymentPerShare) 
        public 
        onlyOwner 
    {
        require(_holders.length > 0, "Empty array cannot be submitted.");
        require(_paymentPerShare > 0, "No Payments per share designated.");

        address issuer = owner(); 

        for (uint256 i = 0; i < _holders.length; i++){
            uint256 securitiesOwned = securityToken.balanceOf(_holders[i]);
            require(securitiesOwned > 0, "Holder does not own any securities.");
            uint256 paymentOwed = securitiesOwned.mul(_paymentPerShare);

            payments[_holders[i]].push(Payment(now, paymentOwed, ChallengeState.NoChallenge));
            stableCoin.transferFrom(issuer, _holders[i], paymentOwed);

            emit PaymentAllocated(_holders[i], paymentOwed);
        }
    }

    /**
	* @dev Allows anyone to check the allotted Payment for a user. 
	* @param _holder Address of holder to check Payment.  
    * @param _index Position of Payment in array of user Payment to check. 
    */
    function checkPayment(address _holder, uint256 _index) 
        public 
        view 
        returns (uint256 timestamp, uint256 value)
    {
        require(payments[_holder].length >= _index, "Supplied index out of range.");
        return (
            payments[_holder][_index].timestamp,
            payments[_holder][_index].value
        );
    }

    /**
	* @dev Allows issuer to challenge the Payment behalf of a security holder. 
	* @param _holder Address of holder to check Payment.  
    * @param _index Position of Payment in array of user Payments to check.
    * @param _sig Returned data from signature of hash of the (holder and index). 
    */
    function relayChallengePayment(
        address _holder,
        uint256 _index,
        bytes _sig
    )
        public
        onlyOwner
    {        
        bytes32 signedHash = keccak256(_holder, _index);
        require(checkSigned(signedHash, _sig, _holder), "Holder has not signed this challenge.");

        Payment[] memory holderPayments = payments[_holder];
        require(holderPayments.length > _index, "Supplied index out of range."); 
        require(holderPayments[_index].timestamp.add(CHALLENGE_PERIOD) <= now, "Challenge period is over.");

        payments[_holder][_index].state = ChallengeState.Challenged;
        emit PaymentChallenged(_holder, holderPayments[_index].value, securityToken.balanceOf(_holder));
    }

    /* 
    - Do we want the _newValue to be calculated here or off-chain? Because originally, 
    we calculate the value on chain. Here it is calculated offchain. 
    - Should the timestamp be reset for the Payment? This would kick off another resolution time.  
    - If the holder has received too much Payment, they must allow this contract to send the 
    difference back to the issuer. 
    */ 
    /**
	* @dev Allows issuer to resolve the Payment record that has been challenged. 
	* @param _holder Address of holder to resolve Payment.  
    * @param _index Position of Payment in array of user Payment to resolve. 
    * @param _newAmount New, corrected amount for the Payment.
    */
    function resolvePaymentRecord(
        address _holder, 
        uint256 _index, 
        uint256 _newAmount
    ) 
        public 
        onlyOwner 
    {    
        require(payments[_holder].length >= _index, "Supplied index out of range."); 

        address issuer = owner(); 

        if (_newAmount > payments[_holder][_index].value) {
            uint256 toSend = _newAmount.sub(payments[_holder][_index].value);
            stableCoin.transferFrom(issuer, _holder, toSend);
            
        } else {
            uint256 toSendBack = payments[_holder][_index].value.sub(_newAmount);
            stableCoin.transferFrom(_holder, issuer, toSendBack);
        }

        payments[_holder][_index].value = _newAmount;
        payments[_holder][_index].state = ChallengeState.Resolved;

        emit PaymentResolved(_holder, _newAmount);
    }

    /**
	* @dev Internal function to verify that data has been signed by a particular user.  
	* @param _rawHash Hash of data that has been signed.  
    * @param _sig The signature data that was returned when the data was signed. 
    * @param _holder Address to check that signed the data. 
    * @return Bool as to whether the _holder signed the provided data. 
    */
    function checkSigned(
        bytes32 _rawHash,
        bytes _sig,
        address _holder
    )
        public
        pure
        returns(bool)
    {
        bytes32 signedHash = _rawHash.toEthSignedMessageHash(); 
        return _holder == signedHash.recover(_sig);
    }
}