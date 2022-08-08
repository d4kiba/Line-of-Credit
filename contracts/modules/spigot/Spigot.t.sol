pragma solidity 0.8.9;

import { Test } from "forge-std/Test.sol";
import { Spigot } from "./Spigot.sol";

import { RevenueToken } from "../../mock/RevenueToken.sol";
import { SimpleRevenueContract } from '../../mock/SimpleRevenueContract.sol';
import { ISpigot } from '../../interfaces/ISpigot.sol';

contract SpigotTest is Test {
    // spigot contracts/configurations to test against
    RevenueToken private token;
    address private revenueContract;
    Spigot private spigot;
    ISpigot.Setting private settings;

    // Named vars for common inputs
    address constant eth = address(0);
    uint256 constant MAX_REVENUE = type(uint).max / 100;
    // function signatures for mock revenue contract to pass as params to spigot
    bytes4 constant opsFunc = SimpleRevenueContract.doAnOperationsThing.selector;
    bytes4 constant transferOwnerFunc = SimpleRevenueContract.transferOwnership.selector;
    bytes4 constant claimPullPaymentFunc = SimpleRevenueContract.claimPullPayment.selector;
    bytes4 constant claimPushPaymentFunc = bytes4(0);

    // create dynamic arrays for function args
    // Mostly unused in tests so convenience for empty array
    bytes4[] private whitelist;
    address[] private c;
    ISpigot.Setting[] private s;

    // Spigot Controller access control vars
    address private owner;
    address private operator;
    address private treasury;

    function setUp() public {
        owner = address(this);
        operator = address(this);
        treasury = address(0xf1c0);
        token = new RevenueToken();

        _initSpigot(address(token), 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        // TODO find some good revenue contracts to mock and deploy
    }

    /**
     * @dev Helper function to initialize new Spigots with different params to test functionality
     */
    function _initSpigot(
        address _token,
        uint8 split,
        bytes4 claimFunc,
        bytes4 newOwnerFunc,
        bytes4[] memory _whitelist
    ) internal {
        // deploy new revenue contract with settings
        revenueContract = address(new SimpleRevenueContract(address(this), address(_token)));

        settings = ISpigot.Setting(_token, split, claimFunc, newOwnerFunc);
       
        spigot = new Spigot(owner, treasury, operator);
        
        // add spigot for revenue contract 
        require(spigot.addSpigot(revenueContract, settings), "Failed to add spigot");

        // give spigot ownership to claim revenue
        revenueContract.call(abi.encodeWithSelector(newOwnerFunc, address(spigot)));
    }


    // Claiming functions

    function testFail_claimRevenue_PullPaymentNoTokenRevenue() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        spigot.claimRevenue(revenueContract, claimData);
    }

    function testFail_claimRevenue_PushPaymentNoTokenRevenue() public {
        _initSpigot(address(token), 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData);
    }

    function testFail_claimRevenue_PushPaymentNoETHRevenue() public {
        _initSpigot(eth, 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData);
    }

    function testFail_claimRevenue_PullPaymentNoETHRevenue() public {
        _initSpigot(eth, 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        spigot.claimRevenue(revenueContract, claimData);
    }

    /**
        @dev only need to test claim function on pull payments because push doesnt call revenue contract
     */
    function testFail_claimRevenue_NonExistantClaimFunction() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(bytes4(0xdebfda05));
        spigot.claimRevenue(revenueContract, claimData);
    }

    function testFail_claimRevenue_MaliciousClaimFunction() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(transferOwnerFunc);
        spigot.claimRevenue(revenueContract, claimData);
    }


    // Claim Revenue - payment split and escrow accounting

    /**
     * @dev helper func to get max revenue payment claimable in Spigot.
     *      Prevents uint overflow on owner split calculations
    */
    function getMaxRevenue(uint256 totalRevenue) internal pure returns(uint256, uint256) {
        if(totalRevenue> MAX_REVENUE) return(MAX_REVENUE, totalRevenue - MAX_REVENUE);
        return (totalRevenue, 0);
    }

    /**
     * @dev helper func to check revenue payment streams to `owner` and `treasury` happened and Spigot is accounting properly.
    */
    function assertSpigotSplits(address _token, uint256 totalRevenue) internal {
        (uint256 maxRevenue, uint256 overflow) = getMaxRevenue(totalRevenue);
        uint256 escrowed = maxRevenue * settings.ownerSplit / 100;

        assertEq(
            spigot.getEscrowBalance(_token),
            escrowed,
            'Invalid escrow amount for spigot revenue'
        );

        assertEq(
            _token == eth ?
                address(spigot).balance :
                RevenueToken(token).balanceOf(address(spigot)),
            escrowed + overflow, // revenue over max stays in contract unnaccounted
            'Spigot balance vs escrow + overflow mismatch'
        );

        assertEq(
            _token == eth ?
                address(treasury).balance :
                RevenueToken(token).balanceOf(treasury),
            maxRevenue - escrowed,
            'Invalid treasury payment amount for spigot revenue'
        );
    }

    function test_claimRevenue_pushPaymentToken(uint256 totalRevenue) public {
        if(totalRevenue == 0) return;

        // send revenue token directly to spigot (push)
        token.mint(address(spigot), totalRevenue);
        assertEq(token.balanceOf(address(spigot)), totalRevenue);
        
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData);

        emit log_named_uint("total revenue: ", totalRevenue);
        assertSpigotSplits(address(token), totalRevenue);
    }

    function test_claimRevenue_pullPaymentToken(uint256 totalRevenue) public {
        if(totalRevenue == 0) return;
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        
        token.mint(revenueContract, totalRevenue); // send revenue
        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        spigot.claimRevenue(revenueContract, claimData);
        
        assertSpigotSplits(address(token), totalRevenue);
        assertEq(token.balanceOf(revenueContract), 0, 'All revenue not siphoned into Spigot');
    }

    /**
     * @dev
     @param totalRevenue - uint96 because that is max ETH in this testing address when dapptools initializes
     */
    function test_claimRevenue_pushPaymentETH(uint96 totalRevenue) public {
        if(totalRevenue == 0) return;
        _initSpigot(eth, 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        payable(address(spigot)).transfer(totalRevenue);
        assertEq(totalRevenue, address(spigot).balance); // ensure spigot received revenue
        
        bytes memory claimData;
        uint256 revenueClaimed = spigot.claimRevenue(revenueContract, claimData); 
        assertEq(totalRevenue, revenueClaimed, 'Improper revenue amount claimed');
        emit log_named_uint("escrowdAmount", spigot.getEscrowBalance(eth));

        
        assertSpigotSplits(eth, totalRevenue);
    }

    function test_claimRevenue_pullPaymentETH(uint96 totalRevenue) public {
        if(totalRevenue == 0) return;
        _initSpigot(eth, 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        payable(revenueContract).transfer(totalRevenue);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        assertEq(totalRevenue, spigot.claimRevenue(revenueContract, claimData), 'invalid revenue amount claimed');

        assertSpigotSplits(eth, totalRevenue);
    }

    
    // Claim escrow 

    function test_claimEscrow_AsOwner(uint256 totalRevenue) public {
        if(totalRevenue == 0) return;
        // send revenue and claim it
        token.mint(address(spigot), totalRevenue);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData);
        assertSpigotSplits(address(token), totalRevenue);

        uint256 claimed = spigot.claimEscrow(address(token));
        (uint256 maxRevenue,) = getMaxRevenue(totalRevenue);

        assertEq(maxRevenue * settings.ownerSplit / 100, claimed, "Invalid escrow claimed");
        assertEq(token.balanceOf(owner), claimed, "Claimed escrow not sent to owner");
    }

    function testFail_claimEscrow_AsNonOwner() public {
        owner = address(0xdebf); // change owner of spigot to deploy
        _initSpigot(address(token), 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        // send revenue and claim it
        token.mint(address(spigot), 10**10);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData);

        // claim fails
        spigot.claimEscrow(address(token));
    }


    function testFail_claimEscrow_UnregisteredToken() public {
        // create new token and send push payment
        RevenueToken fakeToken = new RevenueToken();
        fakeToken.mint(address(spigot), 10**10);

        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData);
        // claim fails because escrowed == 0
        spigot.claimEscrow(address(fakeToken));
    }

  
    
    // Spigot initialization

    function test_addSpigot_ProperSettings() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        (address _token, uint8 _split, bytes4 _claim, bytes4 _transfer) = spigot.getSetting(revenueContract);

        assertEq(settings.token, _token);
        assertEq(settings.ownerSplit, _split);
        assertEq(settings.claimFunction, _claim);
        assertEq(settings.transferOwnerFunction, _transfer);
    }

    function test_addSpigot_OwnerSplitParam(uint8 split) public {
        // Split can only be 0-100 for numerator in percent calculation
        if(split > 100 || split == 0) return;
        // emit log_named_uint("owner split", split);
        _initSpigot(address(token), split, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        // assertEq(spigot.getSetting(revenueContract).ownerSplit, split);
    }

    function testFail_addSpigot_OwnerSplitParam(uint8 split) public {
        // Split can only be 0-100 for numerator in percent calculation
        if(split <= 100) fail();

        _initSpigot(address(token), split, claimPushPaymentFunc, transferOwnerFunc, whitelist);
    }
    
    function testFail_addSpigot_NoTransferFunc() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, bytes4(0), whitelist);
    }

    function test_addSpigot_TransferFuncParam(bytes4 func) public {
        if(func == claimPushPaymentFunc) return;
        _initSpigot(address(token), 100, claimPullPaymentFunc, func, whitelist);

        (,,, bytes4 _transfer) = spigot.getSetting(address(revenueContract));
        assertEq(_transfer, func);
    }

     function testFail_addSpigot_AsNonOwner() public {
        owner =  address(0xdebf);
        
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        spigot.addSpigot(address(0xdebf), settings);
    }

    function testFail_addSpigot_ExistingSpigot() public {
        spigot.addSpigot(revenueContract, settings);
    }

    function testFail_addSpigot_SpigotAsRevenueContract() public {
        spigot.addSpigot(address(spigot), settings);
    }

    // Operate()

    function test_operate_OperatorCanOperate() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        // assertEq(true, spigot.updateWhitelistedFunction(opsFunc, true));
        // assertEq(true, spigot.operate(revenueContract, abi.encodeWithSelector(opsFunc)));
    }

    function testFail_operate_ClaimRevenueFunction() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        
        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        spigot.operate(revenueContract, claimData);
    }
    

    function testFail_operate_AsNonOperator() public {
        operator = address(0xdebf);
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        spigot.operate(revenueContract, claimData);
    }


     function testFail_operate_FailOnNonWhitelistFunc() public {
        spigot.operate(revenueContract, abi.encodeWithSelector(opsFunc));
    }

    function test_updateWhitelistedFunction() public {
        // allow to operate()
        assertTrue(spigot.updateWhitelistedFunction(opsFunc, true));
        // // op()
        assertTrue(spigot.operate(revenueContract, abi.encodeWithSelector(opsFunc)));
    }

    // Release

    function test_removeSpigot() public {
        (address token_,,,) = spigot.getSetting(revenueContract);
        assertEq(address(token), token_);

        spigot.removeSpigot(revenueContract);

        (address token__,,,) = spigot.getSetting(revenueContract);
        assertEq(address(0), token__);
    }


    function testFail_removeSpigot_AsOperator() public {
        operator = address(this); // explicitly test operator can't change
        spigot.updateOwner(address(0xdebf)); // random owner
        
        assertEq(spigot.owner(), address(0xdebf));
        assertEq(spigot.operator(), address(this));
        
        spigot.removeSpigot(revenueContract);
    }

    function testFail_removeSpigot_AsNonOwner() public {
        spigot.updateOwner(address(0xdebf));
        
        assertEq(spigot.owner(), address(0xdebf));
        
        spigot.removeSpigot(revenueContract);
    }


    // Access Control Changes
    function test_updateOwner_AsOwner() public {
        spigot.updateOwner(address(0xdebf));
        assertEq(spigot.owner(), address(0xdebf));
    }

    function test_updateOperator_AsOperator() public {
        spigot.updateOperator(address(0xdebf));
        assertEq(spigot.operator(), address(0xdebf));
    }

    function test_updateTreasury_AsTreasury() public {
        treasury =  address(this);
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        spigot.updateTreasury(address(0xdebf));
        assertEq(spigot.treasury(), address(0xdebf));
    }

    function test_updateTreasury_AsOperator() public {
        spigot.updateTreasury(address(0xdebf));
        assertEq(spigot.treasury(), address(0xdebf));
    }

    function testFail_updateOwner_AsNonOwner() public {
        owner =  address(0xdebf);
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        spigot.updateOwner(address(this));
    }

    function testFail_updateOwner_NullAddress() public {
        spigot.updateOwner(address(0));
    }

    function testFail_updateOperator_AsNonOperator() public {
        operator =  address(0xdebf);
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        spigot.updateOperator(address(this));
    }

    function testFail_updateOperator_NullAddress() public {
        spigot.updateOperator(address(0));
    }

    function testFail_updateTreasury_AsNonTreasuryOrOperator() public {
        treasury =  address(0xdebf);
        operator =  address(0xdebf);

        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        spigot.updateTreasury(address(this));
    }

    function testFail_updateTreasury_NullAddress() public {
        treasury = address(this);

        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        spigot.updateTreasury(address(0));
    }
}
