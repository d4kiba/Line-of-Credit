// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title A vesting contract for full time contributors
/// @author 0xModene
/// @notice You can use this contract to set up vesting for full time DAO contributors
/// @dev All function calls are currently implemented without side effects
contract TokenVesting {
    address public token;
    address public recipient;
    address public treasury;

    uint256 public vestingAmount;
    uint256 public vestingBegin;
    uint256 public vestingCliff;
    uint256 public vestingEnd;

    uint256 public lastUpdate;

    constructor(
        address token_,
        address recipient_,
        address treasury_,
        uint256 vestingAmount_,
        uint256 vestingBegin_,
        uint256 vestingCliff_,
        uint256 vestingEnd_
    ) {
        require(vestingCliff_ >= vestingBegin_, "FTCVester.constructor: cliff is too early");
        require(vestingEnd_ > vestingCliff_, "FTCVester.constructor: end is too early");

        token = token_;
        recipient = recipient_;
        treasury = treasury_;

        vestingAmount = vestingAmount_;
        vestingBegin = vestingBegin_;
        vestingCliff = vestingCliff_;
        vestingEnd = vestingEnd_;

        lastUpdate = vestingBegin;
    }

    modifier onlyTreasury {
        require(msg.sender == treasury, "FTCVester.onlyTreasury: unauthorized");
        _;
    }

    modifier onlyRecipient {
        require(msg.sender == recipient, "FTCVester.onlyRecipient: unauthorized");
        _;
    }

    modifier overCliff {
        require(block.timestamp >= vestingCliff, "FTCVester.overCliff: cliff not reached");
        _;
    }

    /// @notice Sets new recipient address
    /// @param recipient_ new recipient address
    function setRecipient(address recipient_) external onlyRecipient {
        recipient = recipient_;
    }

    /// @notice Sets new treasury address
    /// @param treasury_ new treasury address
    function setTreasury(address treasury_) external onlyTreasury {
        treasury = treasury_;
    }

    /// @notice Allows recipient to claim all currently vested tokens
    function claim() external onlyRecipient overCliff {
        uint256 amount;
        if (block.timestamp >= vestingEnd) {
            amount = IERC20(token).balanceOf(address(this));
        } else {
            amount = vestingAmount * (block.timestamp - lastUpdate) / (vestingEnd - vestingBegin);
            lastUpdate = block.timestamp;
        }
        IERC20(token).transfer(recipient, amount);
    }

    /// @notice Allows treasury to claw back funds in event of separation from recipient
    function clawback() external onlyTreasury {
        IERC20(token).transfer(treasury, IERC20(token).balanceOf(address(this)));
    }
}
