// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract InsuranceService {
    // Consts
    // Assuming every month as 30 days for simplicity
    uint constant monthInSeconds = 60 * 60 * 24 * 30;

    // Structs
    struct InsuranceQuote {
        string insurancType;
        uint insuredAmount;
        uint monthlyPremium;
    }

    struct InsurancePolicy {
        uint quoteIndex;
        address owner;
        uint paidUntil;
        bool active;
    }

    // Storage variables
    uint public usedLiquidity;
    address public provider;
    InsuranceQuote[] public quotes;
    InsurancePolicy[] public policies;

    // Events
    event QuoteCreated(string insurancType, uint insuredAmount, uint monthlyPremium);
    event LiquidityDeposited(uint amount);
    event LiquidityWithdrawn(uint amount);
    event PolicyCreated(uint quoteIndex, address insuree, uint paidUntil);
    event PolicyClosed(uint policyIndex);
    event PolicyPayout(uint policyIndex, uint amount);
    event PolicyPremiumPaid(uint policyIndex, uint newPaidUntil);

    // Constructor
    constructor() payable {
        provider = msg.sender;
    }

    // Views
    function getQuotesLength() public view returns (uint256) {
        return quotes.length;
    }

    function getPoliciesLength() public view returns (uint256) {
        return policies.length;
    }

    // Management Functions
    function createQuote(string calldata insurancType, uint insuredAmount, uint monthlyPremium) external {
        require(msg.sender == provider, "Caller is not provider");

        quotes.push(
            InsuranceQuote(insurancType, insuredAmount, monthlyPremium)
        );

        emit QuoteCreated(insurancType, insuredAmount, monthlyPremium);
    }

    function depositLiquidity() payable external {
        emit LiquidityDeposited(msg.value);
    }
    receive() external payable {
        emit LiquidityDeposited(msg.value);
    }

    function removeLiquidity(uint amount) external {
        require(msg.sender == provider, "Caller is not provider");
        require(amount < address(this).balance - usedLiquidity, "Not enough free liquidity to withdraw provided amount");
        payable(msg.sender).transfer(amount);
        emit LiquidityWithdrawn(amount);
    }

    // This ideally shouldn't be a manual call but coming from an Oracle, but keeping manual for simplicity
    function payout(uint policyIndex, uint amount) external {
        require(msg.sender == provider, "Caller is not provider");
        require(policies.length > policyIndex, "Policy doesn't exist");
        InsurancePolicy storage policy = policies[policyIndex];
        require(policy.active, "Can't pay premium on inactive insurance");
        InsuranceQuote memory quote = quotes[policy.quoteIndex];
        require(amount < quote.insuredAmount, "Can't payout more than insured amount");

        payable(policy.owner).transfer(amount);
        policy.active = false;
        usedLiquidity -= quote.insuredAmount;

        emit PolicyPayout(policyIndex, amount);
        emit PolicyClosed(policyIndex);
    }

    function closePolicy(uint policyIndex) external {
        require(msg.sender == provider, "Caller is not provider");
        require(policies.length > policyIndex, "Policy doesn't exist");
        InsurancePolicy storage policy = policies[policyIndex];
        require(policy.active, "Can't close inactive insurance");
        require(policy.paidUntil < block.timestamp, "Can't close policy up to date on payments");

        InsuranceQuote memory quote = quotes[policy.quoteIndex];
        policy.active = false;
        usedLiquidity -= quote.insuredAmount;
        emit PolicyClosed(policyIndex);
    }

    // User Functions
    function createPolicy(uint quoteIndex) external payable {
        require(quotes.length > quoteIndex, "Quote doesn't exist");
        InsuranceQuote memory quote = quotes[quoteIndex];
        require(msg.value >= quote.monthlyPremium, "Not enough ETH to prepay first month");

        uint paidUntil = block.timestamp + (monthInSeconds * msg.value / quote.monthlyPremium);
        policies.push(
            InsurancePolicy(quoteIndex, msg.sender, paidUntil, true)
        );
        usedLiquidity += quote.insuredAmount;

        emit PolicyCreated(quoteIndex, msg.sender, paidUntil);
    }

    function payPremium(uint policyIndex) external payable {
        require(policies.length > policyIndex, "Policy doesn't exist");
        InsurancePolicy storage policy = policies[policyIndex];
        require(policy.active, "Can't pay premium on inactive insurance");
        require(msg.sender >= policy.owner, "Only insuree can pay premium");

        InsuranceQuote memory quote = quotes[policy.quoteIndex]; 
        uint newPaidUntil = policy.paidUntil + (monthInSeconds * msg.value / quote.monthlyPremium);
        policy.paidUntil = newPaidUntil;

        emit PolicyPremiumPaid(policyIndex, newPaidUntil);
    }
}
