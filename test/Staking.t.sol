// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import "lib/forge-std/src/Test.sol";
import {StakingRewards, IERC20} from "src/StakingRewards.sol";
import {MockERC20} from "test/MockErc20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(
            address(stakingToken),
            address(rewardToken)
        );
        vm.stopPrank();
    }

    function test_alwaysPass() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(
            address(staking.stakingToken()),
            address(stakingToken),
            "Wrong staking token address"
        );
        assertEq(
            address(staking.rewardsToken()),
            address(rewardToken),
            "Wrong reward token address"
        );

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(
            staking.totalSupply(),
            _totalSupplyBeforeStaking + 5e18,
            "totalsupply didnt update correctly"
        );
    }

    function test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(
            staking.balanceOf(bob),
            userStakebefore - 2e18,
            "Balance didnt update correctly"
        );
        assertLt(
            staking.totalSupply(),
            totalSupplyBefore,
            "total supply didnt update correctly"
        );
    }

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward
        vm.warp(block.timestamp + 200);
        // notify rewards
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        // trigger revert
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);

        // trigger second revert
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // trigger first type of flow success
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether) / uint256(1 weeks));
        assertEq(
            staking.finishAt(),
            uint256(block.timestamp) + uint256(1 weeks)
        );
        assertEq(staking.updatedAt(), block.timestamp);

        // trigger setRewards distribution revert
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
    }

    function test_cannot_get_reward0() public {
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        uint256 initialRewardBalance = rewardToken.balanceOf(bob);
        staking.getReward();
        assertEq(
            rewardToken.balanceOf(bob),
            initialRewardBalance,
            "Reward Balance Should Not Change"
        );
    }

    function test_can_get_rewards() public {
        test_notify_Rewards();
        vm.stopPrank();
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        staking.stake(5e18);

        vm.warp(block.timestamp + 1 days);

        uint256 initialRewards = rewardToken.balanceOf(bob);
        staking.getReward();
        uint256 newRewards = rewardToken.balanceOf(bob);
        assertGt(newRewards, initialRewards, "Rewards not updated");
        vm.stopPrank();
    }

    function test_lastTimeRewardApplicable() public {
        test_notify_Rewards();
        vm.stopPrank();

        uint256 currentTime = block.timestamp;
        uint256 finishTime = staking.finishAt();
        assertEq(staking.lastTimeRewardApplicable(), currentTime);

        vm.warp(currentTime + 3 days);
        assertEq(staking.lastTimeRewardApplicable(), currentTime + 3 days);

        vm.warp(finishTime + 1 days);
        assertEq(staking.lastTimeRewardApplicable(), finishTime);
    }

    function test_rewardPerToken() public {
        // Test when totalSupply is 0
        assertEq(staking.rewardPerToken(), 0);

        test_notify_Rewards();
        vm.stopPrank();

        test_can_stake_successfully();
        vm.stopPrank();

        uint256 rewardPerTokenBefore = staking.rewardPerToken();
        vm.warp(block.timestamp + 1 days);
        uint256 rewardPerTokenAfter = staking.rewardPerToken();
        assertGt(rewardPerTokenAfter, rewardPerTokenBefore);
    }

    function test_earned() public {
        test_notify_Rewards();
        vm.stopPrank();

        assertEq(staking.earned(bob), 0);

        test_can_stake_successfully();
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        uint256 earned = staking.earned(bob);
        assertGt(earned, 0, "Should have earned rewards");

        vm.warp(block.timestamp + 1 days);
        assertGt(
            staking.earned(bob),
            earned,
            "Should have earned more rewards"
        );
    }

    function test_notifyRewardAmount_with_remaining_rewards() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        deal(address(rewardToken), owner, 200 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 200 ether);

        staking.notifyRewardAmount(100 ether);
        uint256 firstFinishAt = staking.finishAt();

        vm.warp(block.timestamp + 2 days);

        staking.notifyRewardAmount(50 ether);
        uint256 secondRewardRate = staking.rewardRate();
        uint256 secondFinishAt = staking.finishAt();

        assertGt(secondRewardRate, 0, "Second reward rate should be positive");
        assertGt(
            secondFinishAt,
            firstFinishAt,
            "Second finish time should be later"
        );
        vm.stopPrank();
    }

    function test_withdraw_insufficient_balance() public {
        test_can_stake_successfully();

        vm.expectRevert();
        staking.withdraw(10e18);
        vm.stopPrank();
    }

    function test_comprehensive_staking_flow() public {
        test_notify_Rewards();
        vm.stopPrank();

        address alice = makeAddr("alice");
        deal(address(stakingToken), bob, 10e18);
        deal(address(stakingToken), alice, 20e18);

        // Bob stakes
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        staking.stake(5e18);
        vm.stopPrank();

        // Move time forward
        vm.warp(block.timestamp + 2 days);

        // Alice stakes
        vm.startPrank(alice);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        staking.stake(10e18);
        vm.stopPrank();

        // Move more time forward
        vm.warp(block.timestamp + 2 days);

        // Check both users have earned rewards
        assertGt(staking.earned(bob), 0, "Bob should have earned rewards");
        assertGt(staking.earned(alice), 0, "Alice should have earned rewards");

        // Bob claims rewards
        uint256 bobInitialRewardBalance = rewardToken.balanceOf(bob);
        vm.prank(bob);
        staking.getReward();
        assertGt(
            rewardToken.balanceOf(bob),
            bobInitialRewardBalance,
            "Bob should have received rewards"
        );

        // Bob withdraws partially
        vm.prank(bob);
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), 3e18, "Bob's stake should be reduced");

        // Alice claims and withdraws all
        vm.startPrank(alice);
        staking.getReward();
        staking.withdraw(10e18);
        assertEq(
            staking.balanceOf(alice),
            0,
            "Alice should have no stake left"
        );
        vm.stopPrank();
    }

    function test_rewardPerToken_edge_cases() public {
        assertEq(staking.rewardPerToken(), staking.rewardPerTokenStored());

        test_notify_Rewards();
        vm.stopPrank();

        assertEq(staking.rewardPerToken(), staking.rewardPerTokenStored());

        test_can_stake_successfully();
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        assertGt(staking.rewardPerToken(), staking.rewardPerTokenStored());
    }
}
