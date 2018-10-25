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
        // off-chian payment made at this timestamp
        uint256 timestamp;
        // Value of the payment made
        uint256 value;
        //Hash of wireID, value, receiver, sender, date
        bytes32 offchainPaymentHash; 
        //Storing challenge state in struct for now, defaults to NotChallenged
        ChallengeState state; 
    }

    event PaymentRecorded(address _securityHolder, uint256 _value, bytes32 _offchainPaymentHash);
    event PaymentChallenged(address _securityHolder, bytes32 _offchainPaymentHash, uint256 _oldValue, uint256 _suggestedValue);
    event PaymentResolved(address _securityHolder, bool _paymentChanged);
    event PaymentUpdated(address _securityHolder, uint256 _oldValue, bytes32 _oldHash, uint256 _newValue, bytes32 _newHash);
    
    //Challenge period set to two weeks
    uint256 public constant CHALLENGE_PERIOD = 2 weeks;
    
    //Number not available in array
    int256 public constant DOESNT_EXIST = -1;   

    //The payments each security holder has received
    mapping(address => Payments[]) public payments;

    //Address of security token, required for checking the balance of security tokens per holder
    IERC20 public securityToken;

    /**
	* @dev Constructor to initialize the contract.
	* @param _securityToken Address of security token with which to apply payment.
    * @param _issuer Address of issuer or whoever will be managing payment. 
	*/
    constructor(IERC20 _securityToken, address _issuer) public {
        require(_securityToken != address(0), "Security token address cannot be zero.");
        securityToken = _securityToken;
        transferOwnership(_issuer);
    }
    
    /**
	* @dev Allows issuer to record payment to security holders.
	* @param _securityHolders Array of addresses that are security token holders. 
    * @param _paymentPerSecurity The Payments per security or security token, used to calcuate total Payments owed. 
    * @param _paymentTimestamps The timestamps each of the payments were made at.    
	* @param _offchainPayments Array of hashes of (wire#, value, receiver, sender, date) - proposed info.
    * To Do - Ensure decimal places of USD or units. 
    */
    function recordPayments(
        address[] _securityHolders, 
        uint256 _paymentPerSecurity, 
        uint256[] _paymentTimestamps,
        bytes32[] _offchainPaymentHashes
    ) 
        public 
        onlyOwner 
    {
        require(_securityHolders.length > 0, "Empty array cannot be submitted.");
        require(_paymentPerSecurity > 0, "No payment per security designated.");
        require(_securityHolders.length == _offchainPayments.length == _paymentTimestamps.length, "Arrays must be the same length.");

        for (uint256 i = 0; i < _securityHolders.length; i++){
            uint256 securitiesOwned = securityToken.balanceOf(_securityHolders[i]);
            require(securitiesOwned > 0, "Holder does not own any securities.");
            uint256 paymentValue = securitiesOwned.mul(_paymentPerSecurity);

            payments[_securityHolders[i]].push(
                Payment(_paymentTimestamps[i], paymentValue, _offchainPaymentHashes[i], ChallengeState.NotChallenged)
            );
            emit PaymentRecorded(_securityHolders[i], valueOwed, _offchainPayments[i]);
        }
    }

    /**
	* @dev Allows the front end to calculate the index based on the offchainPayment and holder information. 
    * @param _securityHolder The address whom the payment was for
    * @param _offchainPaymentHash Hashed data of offchain payment. 
    * @return The index of the offchainPayment for the respective security token holder.  
    */
    function lookUpPaymentIndex(address _securityHolder, bytes32 _offchainPaymentHash)
        public
        view
        returns(int256)
    {
        require(_offchainPaymentHash != bytes32(0), "No offchainPayment hash provided.");
        require(_securityHolder != address(0), "No security holder address provided");

        Payment[] memory holderPayments = payments[_securityHolder];
        require (holderPayments.length > 0, "holder has no payment history");

        for (int256 i = holderPayments.length-1; i >= 0; i--){
            if (holderPayments[i].offchainPaymentHash == _offchainPaymentHash)
            {
                return i; 
            } 
        }
        return DOESNT_EXIST;
    }    

    /**
	* @dev Allows issuer to challenge the Payments behalf of a security holder. 
    * @param _offchainPaymentHash Hashed data offchainPayment of Payments. 
    * @param _suggestedValue The value that the holder suggests would be correct. 
    */
    function challengePayment(bytes32 _offchainPaymentHash, uint256 _suggestedValue) public {
        int256 paymentIndex = lookUpPaymentIndex(msg.sender, _offchainPaymentHash);
        require(paymentIndex >= 0, "Payment does not exist for provided hash");
        
        require(payments[msg.sender][paymentIndex].state == ChallengeState.NotChallenged);
        require(payments[msg.sender][paymentIndex].timestamp.add(CHALLENGE_PERIOD) <= now, "Challenge period is over.");
        payments[msg.sender][paymentIndex].state = ChallengeState.Challenged;

        emit PaymentChallenged(msg.sender, _offchainPaymentHash, payments[msg.sender][paymentIndex].value, _suggestedValue);
    }

    /**
	* @dev Allows issuer to resolve the Payments offchainPayment that has been challenged. 
	* @param _securityHolder Address of holder to resolve Payments.  
    * @param _offchainPaymentHash Position of Payments in array of user payment to resolve.
    * @param _updateNeeded Whether the value has changed and a new payment exists
    * @param _newPaymentHash New hash of corrected (wire#, value, receiver, sender, date).
    * @param _newValue New, corrected value for the Payments. Will need to be handled offchain. 
    */
    function resolveChallenge(
        address _securityHolder, 
        bytes32 _offchainPaymentHash, 
        bool _updateNeeded,
        bytes32 _newPaymentHash,
        uint256 _newValue
    ) 
        public 
        onlyOwner 
    {
        int256 paymentIndex = lookUpPaymentIndex(msg.sender, _offchainPaymentHash);
        require(paymentIndex >= 0, "Payment does not exist for provided hash");

        if (_updateNeeded) {
            require(_newOffchainPayment != bytes32(0), "No offchainPayment hash provided."); 
            
            emit PaymentUpdated(
                _securityHolder,
                payments[_securityHolder][paymentIndex].value,
                payments[_securityHolder][paymentIndex].offchainPaymentHash,
                _newValue,
                _newPaymentHash
            );

            payments[_securityHolder][paymentIndex].value = _newValue;
            payments[_securityHolder][paymentIndex].offchainPaymentHash = _newPaymentHash; 

        }
        payments[_securityHolder][paymentIndex].state = ChallengeState.Resolved;

        emit PaymentResolved(_securityHolder, _updateNeeded);
    }

}