import {
    loadFixture, time,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
  
describe("InsuranceService", function () {  
    async function blankContract() {
        // Contracts are deployed using the first signer/account by default
        const [provider, otherAccount] = await ethers.getSigners();
      
        // Deploying with 10 ETH starting capital
        const InsuranceService = await ethers.getContractFactory("InsuranceService");
        const insuranceService = await InsuranceService.deploy({ value: ethers.parseEther("5") });

        return { insuranceService, provider, otherAccount };
    }
  
    it("Insurance Service End-to-End test", async function () {
        const { insuranceService, provider, otherAccount } = await loadFixture(blankContract);
        expect((await insuranceService.quotes).length).to.equal(0);
        expect((await insuranceService.policies).length).to.equal(0);

        // Remove liquidity and add liquidity
        await insuranceService.depositLiquidity({ value: ethers.parseEther("4")})
        await insuranceService.removeLiquidity(ethers.parseEther("1"))
        expect(await ethers.provider.getBalance(await insuranceService.getAddress())).to.equal(ethers.parseEther("8"));

        // Create insurance policies
        await insuranceService.createQuote("WALLET_INSURANCE", ethers.parseEther("1"), ethers.parseEther(".01"));
        await insuranceService.createQuote("WALLET_INSURANCE", ethers.parseEther("5"), ethers.parseEther(".05"));
        await insuranceService.createQuote("COLLATERAL_PROTECTION", ethers.parseEther("1"), ethers.parseEther(".001"));
        await insuranceService.createQuote("COLLATERAL_PROTECTION", ethers.parseEther("5"), ethers.parseEther(".005"));
        let quotesLength = await insuranceService.getQuotesLength();
        expect(quotesLength).to.equal(4);
        expect((await insuranceService.quotes(3)).monthlyPremium).to.equal(ethers.parseEther(".005"));

        // Create 2 policies
        await insuranceService.connect(otherAccount).createPolicy(0, { value: ethers.parseEther("0.01") } )
        await insuranceService.connect(otherAccount).createPolicy(3, { value: ethers.parseEther(".005") } )
        let policiesLength = await insuranceService.getPoliciesLength();
        expect(policiesLength).to.equal(2);
        expect((await insuranceService.policies(0)).owner).to.equal(otherAccount.address);
        let policy = await insuranceService.policies(1)
        expect(policy.quoteIndex).to.equal(3);
        expect(await insuranceService.usedLiquidity()).to.equal(ethers.parseEther("6"));
        expect(await ethers.provider.getBalance(await insuranceService.getAddress())).to.equal(ethers.parseEther("8.015"));

        // Pay premium
        await insuranceService.connect(otherAccount).payPremium(1, { value: ethers.parseEther("0.01") })
        let updatedPolicy = await insuranceService.policies(1)
        expect(policy.paidUntil < updatedPolicy.paidUntil).to.equal(true);
        expect(await ethers.provider.getBalance(await insuranceService.getAddress())).to.equal(ethers.parseEther("8.025"));

        // Payout
        let currentBalance = await ethers.provider.getBalance(otherAccount.address);
        await insuranceService.payout(0, ethers.parseEther(".5"))
        expect((await insuranceService.policies(0)).active).to.equal(false);
        expect(await ethers.provider.getBalance(otherAccount.address)).to.equal(currentBalance + ethers.parseEther("0.5"));
        expect(await insuranceService.usedLiquidity()).to.equal(ethers.parseEther("5"));
        expect(await ethers.provider.getBalance(await insuranceService.getAddress())).to.equal(ethers.parseEther("7.525"));

        // Closing policy after not paid for a while
        await time.increase(60 * 60 * 24 * 100); // Traveling forward through time 100 days 
        await insuranceService.closePolicy(1);
        expect((await insuranceService.policies(1)).active).to.equal(false);
        expect(await insuranceService.usedLiquidity()).to.equal(ethers.parseEther("0"));
    });
});
  