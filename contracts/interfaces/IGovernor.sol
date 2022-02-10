// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {WrappedStakedBandit} from "../tokens/WrappedStakedBandit.sol";

struct Proposal {
        uint256 startBlockNumber; // for snapshot
        uint256 startTime;
        uint256 endTime;
        uint256 totalVotes;
        uint256 forVotes;
        bool executed;
    }

interface IGovernor is IAccessControl {
    function GOVERNOR() external pure returns (bytes32);

    function wsBNDT() external view returns (WrappedStakedBandit);

    function proposalThreshold() external view returns (uint256);

    function quorum() external view returns (uint256);

    function timelockDuration() external view returns (uint256);

    function voteDuration() external view returns (uint256);

    function hasVoted(uint256 proposalID, address user) external view returns (bool);

    function proposalExists(uint256 proposalID) external view returns (bool);

    function proposalIds(uint256 index) external view returns (uint256 proposalID);

    function getProposalDetails(uint256 proposalId) external view returns (Proposal memory);

    function delegate(address delegatee) external;

    function vote(uint256 proposalIndex, bool choice) external;

    function createProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);

    function executeProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256);
}