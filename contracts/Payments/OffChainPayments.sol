pragma solidity 0.4.24; 

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

contract OffChainPayments is Ownable {
    using ECDSA for bytes32; 
    using SafeMath for uint256;

    // Each payment is in one and only one ChallengeState at a time
    enum ChallengeState { NotChallenged, Challenged, Resolved }

    struct Payment {
        // Off-chain payment was made at this timestamp
        uint256 timestamp;
        // Value of the payment made
        uint256 value;
        // Hash of offchain wire-ID, value, receiver, sender, date
        bytes32 offchainPaymentHash; 
        // Whether the payment has been challenged. This defaults to NotChallenged
        ChallengeState state; 
    }

    // This event is used alongside the codes immediately following to specify the event type
    // Not all events require a value or payment hash, constants NO_HASH and NO_NEW_VALUE are used in these cases
    event PaymentEvent(
        address indexed _securityHolder,
        uint256 indexed _index,
        uint256 indexed _eventType,
        uint256 _value,
        bytes32 _offchainPaymentHash
    );
    
    // Event types for the Payment event
    uint256 public constant CREATED = 1;
    uint256 public constant CHALLENGED = 2;
    uint256 public constant RESOLVED_NO_CHANGE = 3;
    uint256 public constant RESOLVED_CHANGED = 4;

    // Constants used in events where no new hash or value is needed
    bytes32 public constant NO_HASH = 0x0;
    uint256 public constant NO_NEW_VALUE = 0;

    // Period within a payee must challenge their payment - customisable
    uint256 public constant CHALLENGE_PERIOD = 2 weeks;
    
    // Returned when a payment doesnt exist in a holder's array of payments
    int256 public constant DOESNT_EXIST = -1;   
    
    // The payments that each security holder has received
    mapping(address => Payment[]) public payments;

    modifier indexInRange(address _payee, uint256 _index) {
        require(payments[_payee].length > _index && _index >= 0, "Payment index not in range for message sender");
        _;
    }

    /**
	* @dev Constructor to initialize the contract.
    * @param _issuer Address of issuer or whoever will be managing payment. 
	*/
    constructor(address _issuer) public {
        transferOwnership(_issuer);
    }
    
    /**
	* @dev Allows issuer to record payment to security holders.
	* @param _securityHolders Array of addresses that are security token holders. 
    * @param _paymentValues The value for each payment that was made off-chain. 
    * @param _paymentTimestamps The timestamps each of the payments were made at.    
	* @param _offchainPaymentHashes Array of hashes of (wire#, value, receiver, sender, date) - proposed info.
    * To Do - Ensure decimal places of USD or units. 
    */
    function recordPayments(
        address[] _securityHolders, 
        uint256[] _paymentValues, 
        uint256[] _paymentTimestamps,
        bytes32[] _offchainPaymentHashes
    ) 
        public 
        onlyOwner 
    {
        require(_securityHolders.length > 0, "Empty array cannot be submitted.");
        require(_securityHolders.length == _offchainPaymentHashes.length, "Arrays must all be the same length.");
        require(_securityHolders.length == _paymentTimestamps.length, "Arrays must be the same length.");
        require(_securityHolders.length == _paymentValues.length, "Arrays must be the same length.");

        for (uint256 i = 0; i < _securityHolders.length; i++) {
            payments[_securityHolders[i]].push(
                Payment(_paymentTimestamps[i], _paymentValues[i], _offchainPaymentHashes[i], ChallengeState.NotChallenged)
            );
            emit PaymentEvent(
                _securityHolders[i], payments[_securityHolders[i]].length-1, CREATED, _paymentValues[i], _offchainPaymentHashes[i]
            );
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

        for (uint256 i = holderPayments.length-1; i >= 0; i--){
            if (holderPayments[i].offchainPaymentHash == _offchainPaymentHash)
            {
                return int256(i); 
            } 
        }
        return DOESNT_EXIST;
    }    

    /**
	* @dev Allows issuer to challenge the Payments behalf of a security holder. 
    * @param _index Hashed data offchainPayment of Payments. 
    * @param _suggestedValue The value that the holder suggests would be correct. 
    */
    function challengePayment(uint256 _index, uint256 _suggestedValue) public indexInRange(msg.sender, _index) {
        require(
            payments[msg.sender][_index].state != ChallengeState.Challenged,
            "Payment already being challenged."
        );
        require(payments[msg.sender][_index].timestamp.add(CHALLENGE_PERIOD) <= now, "Challenge period is over.");
        payments[msg.sender][_index].state = ChallengeState.Challenged;

        emit PaymentEvent(msg.sender, _index, CHALLENGED, _suggestedValue, NO_HASH);
    }

    /**
	* @dev Allows issuer to resolve the Payments offchainPayment that has been challenged. 
	* @param _securityHolder Address of holder to resolve Payments.  
    * @param _index Position of Payments in array of user payment to resolve.
    * @param _newPaymentHash New hash of corrected (wire#, value, receiver, sender, date).
    * @param _newValue New, corrected value for the Payments. Will need to be handled offchain. 
    */
    function resolveChallenge(
        address _securityHolder,
        uint256 _index, 
        bytes32 _newPaymentHash,
        uint256 _newValue
    ) 
        public 
        onlyOwner
        indexInRange(_securityHolder, _index)
    {
        uint256 currentValue = payments[_securityHolder][_index].value;
        if (currentValue == _newValue) {
            emit PaymentEvent(
                _securityHolder,
                _index,
                RESOLVED_NO_CHANGE,
                NO_NEW_VALUE,
                NO_HASH
            );
        } else {
            require(_newPaymentHash != bytes32(0), "No offchainPayment hash provided."); 
            
            emit PaymentEvent(
                _securityHolder,
                _index,
                RESOLVED_CHANGED,
                _newValue,
                _newPaymentHash
            );

            payments[_securityHolder][_index].value = _newValue;
            payments[_securityHolder][_index].offchainPaymentHash = _newPaymentHash; 

        }
        payments[_securityHolder][_index].state = ChallengeState.Resolved;
    }

}