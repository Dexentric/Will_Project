//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "./libraries/AccessControl.sol";
import "./libraries/ReentrancyGuard.sol";
import "./libraries/ERC20.sol";
import "./libraries/ERC721.sol";
/*
0x5B38Da6a701c568545dCfcB03FcB875f56beddC4-testator/owner
0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2-executor/lawyer
0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db-payees1
0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB-payees2
0x617F2E2fD72FD9D5503197092aC168c91465E7f2-payees3
0x17F6AD8Ef982297579C203069C1DbfFE4348c372-payees
0x5c6B0f7Bf3E7ce046039Bd8FABdfD3f9F5021678-payees
*/
contract Will is AccessControl, ReentrancyGuard{
    /// @dev This struct has the useful information of the contract

    struct Manuscript {
        address testator;
        address executor;
        address[] payees;
        bool executed;
        uint256 waitTime;
        uint256 unlockTime;
    }

    /// @dev Define the struct that will be used to know the corresponding equity per ERC20 token (Divided in equal parts)
    struct WillToken {
        IERC20 token;
        uint256 correspondingTokens;
        uint256 tokenBalance;
    }

    /// @dev Define the scruct that will be used to know the corresponding equity per ERC721 token (Divided in equal parts)
    struct WillNFT {
        IERC721 nft;
        uint256 id;
    }
    /// @dev Define the scruct that will be used to know the corresponding ether (Divided in equal parts)
    struct WillEth {
        address eth;
        uint256 id;
    }
    /// @dev bytes32 constants for specific Roles according to AccessControl
    bytes32 public  constant EXECUTOR = keccak256("EXECUTOR");
    //0x9cf85f95575c3af1e116e3d37fd41e7f36a8a373623f51ffaaa87fdd032fa767
    bytes32 public  constant PAYEE = keccak256("PAYEE");
    //0xdd3cf490277a2ed9b8e9d23db09c21bd229077712bc2c8266158d0d92288625a
    bytes32 public   constant OWNER = keccak256("OWNER");
    //0x6270edb7c868f86fda4adedba75108201087268ea345934db8bad688e1feb91b

    uint256 public constant MAX_SUPPLY = 1;

    /// @dev Used to assert that all payees have withdrawn its allocations
    uint8 private totalPayees;

    /// @dev Mapping used to verify no payee address is added twice
    mapping(address => bool) public payeesInWill;

    /// @dev Mapping used to verify no erc20 token is added twice
    mapping(address => bool) public tokensInWill;

    /// @dev Mapping used to verify no erc721 gets assign to same payee
    mapping(address => mapping(address => mapping(uint256 => bool)))
        public nftsInWillPerPayee;

    /// @dev Mapping of Payees => Each NFT assigned (Nft contract and Id)
    mapping(address => WillNFT[]) public willNFTs;

    address[] public checkedPayees;

    uint256 public executorFee;
    uint256 public correspondingEth;

    WillToken[] public willTokens;
    Manuscript public willManuscript;

    /**
     * @notice WillSetted event trigers all info from the manuscript
     * Can be called with WillStatus function or its called automatically after setting up the will
     */
    event WillSetted(address payable[] payees);

    /**
     * @notice WillExecuted event will be emitted once the corresponding executor signer calls
     * the executeWill function to start counting looked time in order to claim the assets
     */
/*
0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db
0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2
*/
     event WillExecuted(
        bool exec,
        address executor,
        uint256 unlockTime,
        uint256 totalBalance,
        uint256 numberOfPayees
    );
    /**
     * @notice Once function withdrawShares is called and the conditions are met:
     * the executeWill function has been executed and unlockTime has passed.
     * Any payee member in the contract will be able to call withdrawShares to claim its assets for everyone
     * and destroy the Will. This event its emmited once and after that the contract will be destroyed.
     */
    event SharesWithdrawn(uint256 ethPerPayee, address caller);
    
    event TokenWithdrawn(address token, address caller, uint256 amount);

    event NFTWithdrawn(address nft, address caller, uint256 id);
    event WillReseted();

    /// Event emited for each payee setted up by the owner in the willStatus function
    event ApprovedPayees(address[] payees);
    /// Event emited after resetting the contract with resetWill and changing executor.
    event ChangedExecutor(address oldExecutor, address newExecutor);
    /// Event emited from willStatus and setWillTokens for each ERC20 token in the will smart contract.
    event ERC20TokensSupplied(address[] tokenAddress);
    /// Event emited after the payee withdraw its shares. When this event its emited this address will no longer be a payee.
    event PayeeChecked(address payee);
    /// Event emited after approving Tokens from NFT Contract with _tokenId array.
    event NFTsApproved(
        IERC721 nftContract,
        uint256[] tokenId,
        address payeeAssigned
    );

    error TokenNotApproved();

    /**
     * @dev The constructor sets up the roles and roles admin
     * This garantees that the main roles are set up in the creation of the smart contract
     * Once created you can add payees and change the executor but only the owner has this privileges
     */
     
    constructor(
        
        address payable _testator,
        address payable _executor,
        uint256 _waitTime
    ) {
        willManuscript.testator = _testator;
        willManuscript.executor = _executor;
        willManuscript.waitTime = _waitTime * 1 days;
        willManuscript.executed = false;
        _setupRole(OWNER, _testator);
        _setupRole(EXECUTOR, _executor);
    }
    /// The will ETH balance must be at least 0.2 ETH and have 1 payee in order to be active
    modifier activeWill() {
        require(address(this).balance > 0.2 ether && willManuscript.payees.length > 0, "This will has not been set up");
        require(!willManuscript.executed, "Will has already been executed");
        _;
    }
    /**
     * @dev Checks the current payees, testator, executor, execution, amount and lock time
     * Should probably manage this status through events
     */
     function willStatus()
        public
        view
        returns (
            address _testator,
            address _executor,
            uint256 _unlockTime,
            bool _executed,
            uint256 _ethBalance
        )
    {
        return (
            willManuscript.testator,
            willManuscript.executor,
            willManuscript.unlockTime,
            willManuscript.executed,
            address(this).balance
        );
    }
    /**
     * @dev The setWill function works as a configuration for the will members and assets
     * This function can only be called from the OWNER
     * You need to provide the contract at least 0.2 ETH in order to be able to set Payees
     */
     function setWill(address payable[] memory _payeesAdd)
        external
        payable
        nonReentrant
        onlyRole(OWNER)
    {
        require(msg.value + address(this).balance >= 0.2 ether,"Minumun balance must be 0.2 ETH");
        require(_payeesAdd.length <= (50 - willManuscript.payees.length),"Max payees are 50");
        require(!willManuscript.executed, "Will has already been executed");
        uint256 _length = _payeesAdd.length;
        for (uint256 i = 0; i < _length; ++i) {
            //ensure that no payee is address 0x00
            require(_payeesAdd[i] != address(0),"The address 0x0 cant be a payee");
            //ensure that the executer is not set as a payee
            require(_payeesAdd[i] != willManuscript.executor,"The executor cant be a payee");
            //ensure that no payee set now have not been added before else display error msg
            require(!payeesInWill[_payeesAdd[i]],
                string(
                    abi.encodePacked(
                        "This payee ",
                        Strings.toHexString(
                            uint160(address(_payeesAdd[i])),
                            20
                        ),
                        " is already in will"
                    )
                )
            );
            //set the the bool val to true that means it is in the will already
            payeesInWill[_payeesAdd[i]] = true;
            //insert the payee to the array
            willManuscript.payees.push(_payeesAdd[i]);
            //give them the role of a payee
            _grantRole(PAYEE, _payeesAdd[i]);
        }
        //emit the event WillSetted
        emit WillSetted(_payeesAdd);
    }
     /**
     * @dev After setting up the will you can load the tokens the Will contract will manage
     * You can set up to 50 different tokens
     * Front end should call the approve function for the contract addresses in _tokenContract before calling this function
     * If the owner approves the token the function will check if the allowence is correctly set to be pushed in to the will.
     * @notice From this function you can add Tokens contract to your will.
     * You need to approve the Token allowance in order to be added to the will.
     * @param _tokenContract The ERC20 contracts you want to add to this Will
     * After calling setWillWillToken with them the approve for each token will pop.
     */
     function setWillToken(address[] memory _tokenContract)
        external
        payable
        onlyRole(OWNER)
        activeWill
    {
        //the max numb of tokens to add is <= 50
        require(willTokens.length <= 50, "The max number of tokens is 50");
        IERC20 tempWillToken;
        uint256 _length = _tokenContract.length;
        for (uint256 i = 0; i < _length; i++) {
            //ensure the token meets the ERC20 standard
            tempWillToken = IERC20(_tokenContract[i]);
            //ensure that a token is not already in the will if not display error msg
            require(
                !tokensInWill[_tokenContract[i]],
                string(
                    abi.encodePacked(
                        "This token ",
                        Strings.toHexString(
                            uint160(address(_tokenContract[i])),
                            20
                        ),
                        " is already in will"
                    )
                )
            );
             /**
            * @dev allowance: Returns the remaining number of tokens that `will contract` will be
            * allowed to spend on behalf of `testator` through {transferFrom}. This is
            * zero by default.
            *
            * This value changes when {approve} or {transferFrom} are called.
            */
            if (
                tempWillToken.allowance(
                    willManuscript.testator,
                    address(this)
                ) == MAX_SUPPLY
            ) {
                tokensInWill[_tokenContract[i]] = true;
                willTokens.push(WillToken(tempWillToken, 0, 0));
            } else {
                revert TokenNotApproved();
            }
            emit ERC20TokensSupplied(_tokenContract);
        }
    }
    /**
     * @notice With this function you can approve the contract to manage your NFTs
     * and assign them to a specific payee in your will, you will need to call this function for each NFT contract/payee you want to add.
     * @param _nftContract The ER721 contract of NFT.
     * @param _tokenId An array of Ids of the contracts NFT that you wish to allow to be assigned.
     * @param _payee The address of the payee that would be assigned these NFTs.
     */
    function setWillNFTs(
        address _nftContract,
        uint256[] memory _tokenId,
        address _payee
    ) external onlyRole(OWNER) activeWill {///@dev only the owner i.e testator can set the nfts to manage
        _checkRole(PAYEE, _payee);
        address payee = _payee;
        uint256 _length = _tokenId.length;
        for (uint256 i = 0; i < _length; i++) {
            ///@dev 
            require(
                !nftsInWillPerPayee[_nftContract][payee][_tokenId[i]],
                string(
                    abi.encodePacked(
                        "This erc721 contract: ",
                        Strings.toHexString(uint160(_nftContract), 20),
                        " id:",
                        _tokenId[i],
                        " is already assigned"
                    )
                )
            );
            IERC721 nftContract = IERC721(_nftContract);
            nftsInWillPerPayee[_nftContract][payee][_tokenId[i]] = true;
            if (nftContract.getApproved(_tokenId[i]) == address(this)) {
                willNFTs[payee].push(WillNFT(nftContract, _tokenId[i]));
            } else {
                revert TokenNotApproved();
            }
            emit NFTsApproved(nftContract, _tokenId, payee);
        }
    }
    /**
     * @dev Execution of will can only be called once.
     * @notice If the owner of the will is deceased (non checkable yet) the executor can execute the will
     * after its executed every payee would need to wait the locked time to withdraw.
     * If the owner its not deceased he can revert the executeWill and change the executor.
     */
    function executeWill() external onlyRole(EXECUTOR) activeWill {
        totalPayees = uint8(willManuscript.payees.length);
        willManuscript.unlockTime = block.timestamp + (willManuscript.waitTime);///@audit look at the vuln
        willManuscript.executed = true;
        updateAllocations();
        emit WillExecuted(
            willManuscript.executed,
            willManuscript.executor,
            willManuscript.unlockTime,
            address(this).balance,
            willManuscript.payees.length
        );
    }
    /// @dev Updates the dividends of the payees and the lawyer fee (10% of the total balance)
    function updateAllocations() private {
        executorFee = address(this).balance / 10;///@dev the lawyer's fee is set
        correspondingEth =
            (address(this).balance - executorFee) /
            willManuscript.payees.length;
    }
    /**
     * @dev Updates the dividends of the payees for each token in the contract once executed
     * The Allocations are based on the current balance of the testator.
     */
    function updateTokensAllocations() private {
        uint256 tokenBalanace;
        uint256 _length = willTokens.length;
        for (uint256 i = 0; i <= _length - 1; ) {
            /// @dev if the balance of the testator is not equal to the number of tokens in the will
            if (
                willTokens[i].tokenBalance !=
                IERC20(willTokens[i].token).balanceOf(
                    address(willManuscript.testator)
                )
            ) {
                /// @dev set tokenBalance to balance of the testator
                tokenBalanace = IERC20(willTokens[i].token).balanceOf(
                    address(willManuscript.testator)
                );
                /// @dev split the tokens equally among the payees
                willTokens[i].correspondingTokens =
                    tokenBalanace /
                    willManuscript.payees.length;
                /// @dev set 
                willTokens[i].tokenBalance = tokenBalanace;
            }
            /// @dev we are deleting the token if it is 0
            if (willTokens[i].tokenBalance == 0) {
                WillToken memory tempToken = willTokens[i];
                /// @dev set the token to the last element in the array
                willTokens[i] = willTokens[_length - 1];
                /// @dev set the temptoken to it
                willTokens[_length - 1] = tempToken;
                /// @dev remove it
                willTokens.pop();
                _length = willTokens.length;
                i = 0;
            } else i++;
            if (_length == 0) break;
        }
    }
    /**
     * @dev Check the ownership of ER721 tokens declared in the will if they are no longer
     * from the testator deletes them from the array of its corresponding payee.
     * In case all NFTs in the array gets deleted the loop breaks for the payee.
     */
    function updateNFTAllocations() private {
        address _payeeChecking = msg.sender;
        uint256 _length = willNFTs[_payeeChecking].length;
        for (uint256 k = 0; k <= _length - 1; ) {
            /// @dev checks if the nft is still owned by the testator
            if (
                (willNFTs[_payeeChecking][k].nft.ownerOf(
                    willNFTs[_payeeChecking][k].id
                ) != willManuscript.testator) &&
                willNFTs[_payeeChecking].length != 0
            ) {
                WillNFT memory tempNFT = willNFTs[_payeeChecking][k];
                willNFTs[_payeeChecking][k] = willNFTs[_payeeChecking][
                    _length - 1
                ];
                willNFTs[_payeeChecking][_length - 1] = tempNFT;
                willNFTs[_payeeChecking].pop();
                _length = willNFTs[_payeeChecking].length;
                k = 0;
            } else k++;
            if (_length == 0) break;
        }
    }
    /**
     * @notice The payee can withdraw his part when the will is executed and the locked time has passed.
     * Each payee will need to call this function in order to claim its ETH, Tokens and NFTs.
     * When the last payee executes this function the contract will destroy itself
     * and transfer the remaining ETH (The executor fee) to the executor.
     */
    function withdrawShares() external onlyRole(PAYEE) nonReentrant {
        require(willManuscript.executed, "Will has not been executed yet");
        require(payeesInWill[msg.sender], "You have already withdrawn");
        require(
            block.timestamp >= willManuscript.unlockTime,
            "Will hasnt been unlocked yet"
        );
        bool sent;
        if (willTokens.length > 0) {
            updateTokensAllocations();
            uint256 _lengthj = willTokens.length;
            for (uint256 j = 0; j < _lengthj; ++j) {
                // send amount from testator to caller of this function i.e payee
                sent = willTokens[j].token.transferFrom(
                    address(willManuscript.testator),
                    msg.sender,
                    willTokens[j].correspondingTokens
                );
                /// @dev Require added to prevent selfdestruct when an error happens
                require(
                    sent,
                    string(
                        abi.encodePacked(
                            "Failed to send",
                            Strings.toHexString(
                                uint160(address(willTokens[j].token)),
                                20
                            ),
                            "token"
                        )
                    )
                );
                emit TokenWithdrawn(
                    address(willTokens[j].token),
                    msg.sender,
                    willTokens[j].correspondingTokens
                );
            }
        }
        if (willNFTs[msg.sender].length > 0) {
            updateNFTAllocations();
            uint256 _lengthk = willNFTs[msg.sender].length;
            for (uint256 k = 0; k < _lengthk; k++) {
                willNFTs[msg.sender][k].nft.safeTransferFrom(
                    address(willManuscript.testator),
                    msg.sender,
                    willNFTs[msg.sender][k].id
                );
                emit NFTWithdrawn(
                    address(willNFTs[msg.sender][k].nft),
                    msg.sender,
                    willNFTs[msg.sender][k].id
                );
            }
        }
        payeeChecked();
        (sent, ) = payable(msg.sender).call{value: correspondingEth}("");
        /// @dev Require added to prevent selfdestruct when an error happens
        require(sent, "Failed to send Ether");
        emit SharesWithdrawn(correspondingEth, msg.sender);
        if (willManuscript.payees.length == 0)
            selfdestruct(payable(willManuscript.executor));
    }

    /// @dev Deletes payee from array in willManuscript and revoke its PAYEE role.
    function payeeChecked() private {
        uint256 _length = willManuscript.payees.length;
        address _payee = msg.sender;
        for (uint256 i = 0; i <= _length - 1; ++i) {
            if (willManuscript.payees[i] == _payee) {
                willManuscript.payees[i] = willManuscript.payees[_length - 1];
                willManuscript.payees[_length - 1] = _payee;
                willManuscript.payees.pop();
                _length = willManuscript.payees.length;
                payeesInWill[msg.sender] = false;
                emit PayeeChecked(_payee);
                renounceRole(PAYEE, _payee);
            }
            if (_length == 0) break;
        }
    }

    /**
     * @notice If the will has been executed and the Testator wants to revert it he can call this function.
     * The executed will bool and the unlockTime will be set to 0.
     * If at least one payee withdraw its shares you wont be able to call this function anymore since the contract Will
     * its already executing.
     */
    function resetWill() external onlyRole(OWNER) {
        require(
            willManuscript.payees.length == totalPayees,
            "At least one payee has withdrawn"
        );
        willManuscript.executed = false;
        willManuscript.unlockTime = 0;
        emit WillReseted();
    }

    /**
     * @notice This function replaces the Executor for a new address.
     * Keep in mind that the old executor cant be assign again as new executor.
     * @param _newExecutor The address of the new executor that will be assigned to this Will Contract.
     */
    function replaceExecutor(address payable _newExecutor)
        external
        onlyRole(OWNER)
    {
        if (_newExecutor == willManuscript.executor)
            revert("Cant be same executor");
        address _oldExecutor = willManuscript.executor;
        willManuscript.executor = _newExecutor;
        _revokeRole(EXECUTOR, _oldExecutor);
        _grantRole(EXECUTOR, willManuscript.executor);
        emit ChangedExecutor(_oldExecutor, _newExecutor);
    }

    /**
     * @notice Function to reclaim the balance from the owner (Testator)
     * This function will transfer all ETH to the OWNER and destroy the will Contract.
     * @dev The approved tokens and NFTs should not be concerned since the contract will be no longer reacheable.
     */
    function revokeWill() external onlyRole(OWNER) {
        selfdestruct(payable(willManuscript.testator));
    }
}
