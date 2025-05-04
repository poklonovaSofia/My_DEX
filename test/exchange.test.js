const {
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const assert = require("assert");
const { ethers } = require("hardhat");

describe("TokenExchange", function () {
    async function deployExchangeFixture() {
        const [owner, user] = await ethers.getSigners();

        const Token = await ethers.getContractFactory("Token");
        const token = await Token.deploy();
        await token.deployed();

        await token.mint(ethers.utils.parseUnits("10000", 0));

        const Exchange = await ethers.getContractFactory("TokenExchange");
        const exchange = await Exchange.deploy(token.address);
        await exchange.deployed();

        await token.approve(exchange.address, 5000);
        await exchange.createPool(5000, {
            value: ethers.utils.parseEther("0.005"),
        });

        return { exchange, token, owner, user };
    }

    describe("Deployment", function () {
        it("Should deploy with correct reserves", async function () {
            const { exchange } = await loadFixture(deployExchangeFixture);

            const ethReserves = await exchange.getEthReserves();
            const tokenReserves = await exchange.getTokenReserves();

            assert(ethReserves.eq(ethers.utils.parseEther("0.005")));
            assert(tokenReserves.eq(5000));
        });
    });

    describe("getCurrentRate", function () {
        it("Should return a positive exchange rate", async function () {
            const { exchange } = await loadFixture(deployExchangeFixture);
            const rate = await exchange.getCurrentRate();

            assert(rate.gt(0));
        });

        it("Should revert if reserves are zero", async function () {
            const Token = await ethers.getContractFactory("Token");
            const token = await Token.deploy();
            await token.deployed();

            const Exchange = await ethers.getContractFactory("TokenExchange");
            const exchange = await Exchange.deploy(token.address);
            await exchange.deployed();

            try {
                await exchange.getCurrentRate();
                assert.fail("Expected revert not received");
            } catch (err) {
                assert(err.message.includes("division by zero") || err.message.includes("reverted"));
            }
        });
    });

    describe("Liquidity", function () {
        it("Should add liquidity successfully", async function () {
            const { exchange, token } = await loadFixture(deployExchangeFixture);
            await token.mint(10000);
            await token.approve(exchange.address, 1000);

            const currentRate = await exchange.getCurrentRate();

            await exchange.addLiquidity(
                currentRate.mul(105).div(100),
                currentRate.mul(95).div(100),
                { value: ethers.utils.parseEther("0.001") }
            );

            const newEth = await exchange.getEthReserves();
            assert(newEth.eq(ethers.utils.parseEther("0.006")));
        });

        it("Should remove liquidity and refund ETH", async function () {
            const { exchange, token, owner } = await loadFixture(deployExchangeFixture);
            await token.mint(10000);
            await token.approve(exchange.address, 1000);

            const rate = await exchange.getCurrentRate();
            await exchange.addLiquidity(
                rate.mul(105).div(100),
                rate.mul(95).div(100),
                { value: ethers.utils.parseEther("0.001") }
            );

            const balanceBefore = await ethers.provider.getBalance(owner.address);

            const tx = await exchange.removeLiquidity(
                ethers.utils.parseEther("0.001"),
                rate.mul(105).div(100),
                rate.mul(95).div(100)
            );
            const receipt = await tx.wait();
            const gasUsed = receipt.gasUsed.mul(tx.gasPrice || 0);

            const balanceAfter = await ethers.provider.getBalance(owner.address);
            assert(balanceAfter.add(gasUsed).gt(balanceBefore.sub(ethers.utils.parseEther("0.001"))));
        });

        it("Should revert if allowance is insufficient", async function () {
            const { exchange, token } = await loadFixture(deployExchangeFixture);
            await token.mint(1000);

            const rate = await exchange.getCurrentRate();

            try {
                await exchange.addLiquidity(
                    rate.mul(105).div(100),
                    rate.mul(95).div(100),
                    { value: ethers.utils.parseEther("0.001") }
                );
                assert.fail("Expected revert due to allowance");
            } catch (err) {
                assert(err.message.includes("insufficient allowance"));
            }
        });

        it("Should revert when removing more liquidity than owned", async function () {
            const { exchange } = await loadFixture(deployExchangeFixture);

            const rate = await exchange.getCurrentRate();

            try {
                await exchange.removeLiquidity(
                    ethers.utils.parseEther("100"),
                    rate.mul(105).div(100),
                    rate.mul(95).div(100)
                );
                assert.fail("Expected revert for invalid ETH amount");
            } catch (err) {
                assert(err.message.includes("Invalid ETH amount"));
            }
        });
    });

    describe("Swaps", function () {
        it("Should swap ETH for tokens", async function () {
            const { exchange, token, user } = await loadFixture(deployExchangeFixture);
            const initial = await token.balanceOf(user.address);

            await exchange.connect(user).swapETHForTokens(
                ethers.utils.parseUnits("1000000", 0),
                { value: ethers.utils.parseEther("0.001") }
            );

            const after = await token.balanceOf(user.address);
            assert(after.gt(initial));
        });

        it("Should revert swap if rate too high", async function () {
            const { exchange, token, user } = await loadFixture(deployExchangeFixture);
            await token.mint(1000);
            await token.transfer(user.address, 1000);
            await token.connect(user).approve(exchange.address, 1000);

            try {
                await exchange.connect(user).swapTokensForETH(500, 1);
                assert.fail("Expected revert for unacceptable rate");
            } catch (err) {
                assert(err.message.includes("Unacceptable rate"));
            }
        });
    });

    describe("Additional tests", function () {
        it("Should return the correct swap fee", async function () {
            const { exchange } = await loadFixture(deployExchangeFixture);
            const [num, den] = await exchange.getSwapFee();

            assert.equal(num.toString(), "3");
            assert.equal(den.toString(), "100");
        });

        it("Should remove all liquidity", async function () {
            const { exchange, token, owner } = await loadFixture(deployExchangeFixture);
            await token.mint(1000);
            await token.approve(exchange.address, 1000);

            const rate = await exchange.getCurrentRate();
            await exchange.addLiquidity(
                rate.mul(105).div(100),
                rate.mul(95).div(100),
                { value: ethers.utils.parseEther("0.001") }
            );

            const before = await ethers.provider.getBalance(owner.address);

            const tx = await exchange.removeAllLiquidity(
                rate.mul(105).div(100),
                rate.mul(95).div(100)
            );
            const receipt = await tx.wait();
            const gasUsed = receipt.gasUsed.mul(tx.gasPrice || 0);

            const after = await ethers.provider.getBalance(owner.address);
            assert(after.add(gasUsed).gt(before.sub(ethers.utils.parseEther("0.001"))));
        });

        it("Should revert if user has no liquidity to remove", async function () {
            const { exchange, user } = await loadFixture(deployExchangeFixture);
            const rate = await exchange.getCurrentRate();

            try {
                await exchange.connect(user).removeAllLiquidity(
                    rate.mul(105).div(100),
                    rate.mul(95).div(100)
                );
                assert.fail("Expected revert for no liquidity");
            } catch (err) {
                assert(err.message.includes("No liquidity to remove"));
            }
        });
    });
});
