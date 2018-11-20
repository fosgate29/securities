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

    event PaymentRecorded(address indexed _securityHolder, uint256 indexed _index, uint256 _value, bytes32 _offchainPaymentHash);
    event PaymentChallenged(address indexed _securityHolder, uint256 indexed _index, uint256 _suggestedValue);
    event PaymentResolved(address indexed _securityHolder, uint256 indexed _index, bool _paymentChanged);
    event PaymentUpdated(address indexed _securityHolder, uint256 indexed _index, uint256 _newValue, bytes32 _newHash);
    
    //Challenge period set to two weeks
    uint256 public constant CHALLENGE_PERIOD = 2 weeks;
    
    //Number not available in array
    int256 public constant DOESNT_EXIST = -1;   

    //The payments each security holder has received
    mapping(address => Payment[]) public payments;

    //Address of security token, required for checking the balance of security tokens per holder
    IERC20 public securityToken;

    modifier indexInRange(address _payee, uint256 _index) {
        require(payments[_payee].length > _index && _index >= 0, "Payment index not in range for message sender");
        _;
    }

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
	* @param _offchainPaymentHashes Array of hashes of (wire#, value, receiver, sender, date) - proposed info.
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
        require(
            (_securityHolders.length == _offchainPaymentHashes.length) && (_offchainPaymentHashes.length == _paymentTimestamps.length),
            "Arrays must be the same length."
        );
        for (uint256 i = 0; i < _securityHolders.length; i++){
            uint256 securitiesOwned = securityToken.balanceOf(_securityHolders[i]);
            require(securitiesOwned > 0, "Holder does not own any securities.");
            uint256 paymentValue = securitiesOwned.mul(_paymentPerSecurity);

            payments[_securityHolders[i]].push(
                Payment(_paymentTimestamps[i], paymentValue, _offchainPaymentHashes[i], ChallengeState.NotChallenged)
            );
            emit PaymentRecorded(_securityHolders[i], payments[_securityHolders[i]].length-1, paymentValue, _offchainPaymentHashes[i]);
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
        require(payments[msg.sender][_index].state == ChallengeState.NotChallenged);
        require(payments[msg.sender][_index].timestamp.add(CHALLENGE_PERIOD) <= now, "Challenge period is over.");
        payments[msg.sender][_index].state = ChallengeState.Challenged;

        emit PaymentChallenged(msg.sender, _index, _suggestedValue);
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
        bool updated = true;
        if (currentValue == _newValue) {
            updated = false;
        } else {
            require(_newPaymentHash != bytes32(0), "No offchainPayment hash provided."); 
            
            emit PaymentUpdated(
                _securityHolder,
                _index,
                _newValue,
                _newPaymentHash
            );

            payments[_securityHolder][_index].value = _newValue;
            payments[_securityHolder][_index].offchainPaymentHash = _newPaymentHash; 

        }
        payments[_securityHolder][_index].state = ChallengeState.Resolved;
        emit PaymentResolved(_securityHolder, _index, updated);
    }

}