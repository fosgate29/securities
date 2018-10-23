pragma solidity 0.4.24; 

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

contract OffChainPayments is Ownable {
    using ECDSA for bytes32; 
    using SafeMath for uint256;

    enum ChallengeState { NotChallenged, Challenged, Resolved }

    struct Payment {
        // Payment recorded at this time
        uint256 timeRecorded;
        // off-chian payment made at this time
        uint256 timeOfPayment;
        // Value of the payment made 
        uint256 value;
        //Hash of wireID, amount, receiver, sender, date
        bytes32 offchainPayment; 
        //Storing challenge state in struct for now, defaults to NotChallenged
        ChallengeState state; 
    }

    event PaymentRecorded(address _securityHolder, uint256 _paymentAmount, bytes32 _offchainPaymentHash);
    event PaymentChallenged(address _securityHolder, uint256 _paymentAmount, uint256 _securityAmountOwned, bytes32 _offchainPaymentHash);
    event PaymentResolved(address _securityHolder, uint256 _newPaymentsAmount, bytes32 _offchainPaymentHash);
    
    //Challenge period set to two weeks
    uint256 public constant CHALLENGE_PERIOD = 2 weeks;
    
    //Number not available in array
    int256 public constant NotAvailable = -1;   

    //Address will be per each security token holder
    mapping(address => Payments[]) public payments;

    //Address of security token, required for checking the balance of security tokens per holder
    IERC20 public securityToken;

    /**
	* @dev Constructor to initialize the contract.
	* @param _securityToken Address of security token with which to apply payment.
    * @param _issuer Address of issuer or whomever will be managing payment. 
	*/
    constructor(IERC20 _securityToken, address _issuer) public {
        require(_securityToken != address(0), "Security token address cannot be zero.");
        securityToken = _securityToken;
        transferOwnership(_issuer);
    }
    
    /**
	* @dev Allows issuer to record payment to security holders.
	* @param _holders Array of addresses that are security token holders. 
    * @param _paymentPerSecurity The Payments per security or security token, used to calcuate total Payments owed. 
	* @param _offchainPayments Array of hashes of (wire#, amount, receiver, sender, date) - proposed info.
    * To Do - Ensure decimal places of USD or units. 
    */
    function recordPayments(
        address[] _holders, 
        uint256 _paymentPerSecurity, 
        bytes32[] _offchainPayments
    ) 
        public 
        onlyOwner 
    {
        require(_holders.length > 0, "Empty array cannot be submitted.");
        require(_paymentPerSecurity > 0, "No payment per security designated.");
        require(_holders.length == _offchainPayments.length, "Arrays must be the same length.");

        for (uint256 i = 0; i < _holders.length; i++){
            uint256 securitiesOwned = securityToken.balanceOf(_holders[i]);
            require(securitiesOwned > 0, "Holder does not own any securities.");
            uint256 amountOwed = securitiesOwned.mul(_paymentPerSecurity);

            payments[_holders[i]].push(Payment(now, amountOwed, _offchainPayments[i], ChallengeState.NotChallenged));
            emit PaymentRecorded(_holders[i], amountOwed, _offchainPayments[i]);
        }
    }

    /**
	* @dev Allows the front end to calculate the index based on the offchainPayment and holder information. 
	* @param _holder Address of holder to check Payments.  
    * @param _offchainPayment Hashed data offchainPayment of Payments. 
    * @return The index of the offchainPayment for the respective security token holder.  
    */
    function lookUpPaymentIndex(address _holder, bytes32 _offchainPayment)
        public
        view
        returns(int256)
    {
        Payment[] memory holderPayments = payments[_holder];
         
        uint256 i = holderPayments.length-1;
        while (i >= 0) {
            if (holderPayments[i].offchainPayment == _offchainPayment)
            {
                return int256(i); 
            } 
            else if (i == 0 && holderPayments[i].offchainPayment != _offchainPayment) {
                return -1;
            }
            i--;
        }
    }    

    /**
	* @dev Allows anyone to check the allotted Payments for a user. 
	* @param _holder Address of holder to check Payments.  
    * @param _index Position of Payments in array of user payment to check. 
    */
    function checkPayment(address _holder, uint256 _index) 
        public 
        view 
        returns (uint256 timeRecorded, uint256 value, bytes32 offchainPayment)
    {
        require(payments[_holder].length > _index, "Supplied index out of range.");
        return (
            payments[_holder][_index].timeRecorded,
            payments[_holder][_index].value,
            payments[_holder][_index].offchainPayment
        );
    }

    /**
	* @dev Allows issuer to challenge the Payments behalf of a security holder. 
	* @param _holder Address of holder to check Payments.  
    * @param _index Position of Payments in array of user payment to check.
    * @param _offchainPayment Hashed data offchainPayment of Payments. 
    * @param _sig Returned data from signature of hash of the (holder, index, and offchainPayment). 
    */
    function relayChallengePayment(
        address _holder,
        uint256 _index,
        bytes32 _offchainPayment,
        bytes _sig
    )
        public
        onlyOwner
    {
        require(_offchainPayment != bytes32(0), "No offchainPayment hash provided.");
        
        bytes32 signedHash = keccak256(_holder, _index, _offchainPayment);
        require(checkSigned(signedHash, _sig, _holder), "Holder has not signed this challenge.");

        Payment[] memory holderpayment = payments[_holder];
        require(holderpayment.length > _index, "Supplied index out of range."); 
        require(holderpayment[_index].offchainPayment == _offchainPayment, "Supplied offchainPayment cannot be located.");
        require(holderpayment[_index].timeRecorded.add(CHALLENGE_PERIOD) <= now, "Challenge period is over.");

        payments[_holder][_index].state = ChallengeState.Challenged;
        emit PaymentChallenged(_holder, holderpayment[_index].value, securityToken.balanceOf(_holder), holderpayment[_index].offchainPayment);
    }

    /**
	* @dev Allows issuer to resolve the Payments offchainPayment that has been challenged. 
	* @param _holder Address of holder to resolve Payments.  
    * @param _index Position of Payments in array of user payment to resolve. 
    * @param _newOffchainPayment New hash of corrected (wire#, amount, receiver, sender, date).
    * @param _newAmount New, corrected amount for the Payments. Will need to be handled offchain. 
    */
    function resolvePayment(
        address _holder, 
        uint256 _index, 
        bytes32 _newOffchainPayment,
        uint256 _newAmount
    ) 
        public 
        onlyOwner 
    {
        require(_newOffchainPayment != bytes32(0), "No offchainPayment hash provided.");
        
        require(payments[_holder].length > _index, "Supplied index out of range."); 
        //Do we want to update the timeRecorded as well?
        payments[_holder][_index].value = _newAmount;
        payments[_holder][_index].offchainPayment = _newOffchainPayment; 
        payments[_holder][_index].state = ChallengeState.Resolved;

        emit PaymentResolved(_holder, _newAmount, _newOffchainPayment);
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