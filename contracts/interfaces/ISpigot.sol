pragma solidity ^0.8.9;

interface ISpigot {
    struct Setting {
        uint8 ownerSplit; // x/100 % to Owner, rest to Treasury
        bytes4 claimFunction; // function signature on contract to call and claim revenue
        bytes4 transferOwnerFunction; // function signature on contract to call and transfer ownership
    }

    // Spigot Events

    event AddSpigot(address indexed revenueContract, uint256 ownerSplit);

    event RemoveSpigot(address indexed revenueContract, address token);

    event UpdateWhitelistFunction(bytes4 indexed func, bool indexed allowed);

    event UpdateOwnerSplit(
        address indexed revenueContract,
        uint8 indexed split
    );

    event ClaimRevenue(
        address indexed token,
        uint256 indexed amount,
        uint256 escrowed,
        address revenueContract
    );

    event ClaimEscrow(
        address indexed token,
        uint256 indexed amount,
        address owner
    );

    // Stakeholder Events

    event UpdateOwner(address indexed newOwner);

    event UpdateOperator(address indexed newOperator);

    event UpdateTreasury(address indexed newTreasury);

    // Errors
    error BadFunction();

    error OperatorFnNotWhitelisted();

    error OperatorFnNotValid();

    error OperatorFnCallFailed();

    error ClaimFailed();

    error NoRevenue();

    error UnclaimedRevenue();

    error CallerAccessDenied();

    error BadSetting();

    // ops funcs

    function claimRevenue(
        address revenueContract,
        address token,
        bytes calldata data
    ) external returns (uint256 claimed);

    function operate(address revenueContract, bytes calldata data)
        external
        returns (bool);

    // owner funcs
    function claimEscrow(address token) external returns (uint256 claimed);

    function addSpigot(address revenueContract, Setting memory setting)
        external
        returns (bool);

    function removeSpigot(address revenueContract) external returns (bool);

    // stakeholder funcs

    function updateOwnerSplit(address revenueContract, uint8 ownerSplit)
        external
        returns (bool);

    function updateOwner(address newOwner) external returns (bool);

    function updateOperator(address newOperator) external returns (bool);

    function updateTreasury(address newTreasury) external returns (bool);

    function updateWhitelistedFunction(bytes4 func, bool allowed)
        external
        returns (bool);

    // Getters
    function owner() external view returns (address);

    function treasury() external view returns (address);

    function operator() external view returns (address);

    function isWhitelisted(bytes4 func) external view returns (bool);

    function getEscrowed(address token) external view returns (uint256);

    function getSetting(address revenueContract)
        external
        view
        returns (
            uint8 split,
            bytes4 claimFunc,
            bytes4 transferFunc
        );
}
